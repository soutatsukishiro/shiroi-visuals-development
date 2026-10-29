#ifndef LIGHTCOLOR_GLSL
#define LIGHTCOLOR_GLSL
// Coloured block light (COLORED_LIGHT) and the light of a held torch (HAND_LIGHT), a cheap alternative to real point
// lights. The game's block lightmap keeps the intensity (walls still block it) and only its colour comes from the
// lights around:
//  1. every face of a light source (block ids 4, 5, 6) seen by the terrain pass adds the colour of its own bright,
//     saturated texels (the flame, not the stick) to a grid of 2 block cells around the camera (SSBO, LC_SPLAT). The
//     shadow pass sees the lights behind the camera too, but feeding it cost every shadow vertex an extra attribute
//     (+0.8 ms with a large world): instead the grid remembers the colours it has seen for a few seconds
//  2. three compute passes spread it with a Gaussian of ~5 blocks and blend it into that memory, which follows the
//     camera (prepare2..4, program/lightcolor_spread.glsl; ping-pong lcC / lcD)
//  3. shading takes the mean colour there, relative to a plain torch's, so torches keep their light and soul, copper
//     and redstone torches, soul fire, amethyst... tint it (LC_SAMPLE, lib/shading.glsl)
#include "/lib/common.glsl"

const ivec3 LC_GRID = ivec3(64, 32, 64);   // cells (128 x 64 x 128 blocks around the camera)
const float LC_CELL = 2.0;                   // blocks per cell
const vec3  LC_TORCH_HUE = vec3(1.0, 0.8, 0.36);   // the plain torch's flame (what the block light colour is made for)

ivec3 lcOrigin(vec3 camera) { return ivec3(floor(camera / LC_CELL)) - LC_GRID / 2; }

#ifdef LC_SPLAT
layout(std430, binding = 5) buffer LightSplat { uint lcSplat[]; };   // 4 per cell: r, g, b, weight (x 64)

// called by one corner of every quad of a light source: the colour of its bright texels (weighted by brightness above
// 0.55 and saturation, as the flame of a torch is) inside the quad's own part of the sprite
void lightSplat(sampler2D tex, vec2 uv, vec2 midUv, vec3 playerPos) {
    vec2 size = vec2(textureSize(tex, 0));
    vec2 halfUv = abs(uv - midUv);
    ivec2 lo = ivec2(floor((midUv - halfUv) * size + 0.5));
    ivec2 sz = max(ivec2(floor(halfUv * 2.0 * size + 0.5)), ivec2(1));
    vec4 acc = vec4(0.0);
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
        vec4 c = texelFetch(tex, lo + (ivec2(i, j) * 2 + 1) * sz / 8, 0);
        if (c.a < 0.1) continue;
        float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
        float w = max(mx - 0.55, 0.0) * (0.25 + (mx > 0.0 ? (mx - mn) / mx : 0.0));
        acc += vec4(c.rgb * w, w);
    }
    if (acc.w <= 0.0) return;
    ivec3 cell = ivec3(floor((playerPos + cameraPosition) / LC_CELL)) - lcOrigin(cameraPosition);
    if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, LC_GRID))) return;
    int i = ((cell.z * LC_GRID.y + cell.y) * LC_GRID.x + cell.x) * 4;
    uvec4 q = uvec4(acc * 64.0 + 0.5);
    atomicAdd(lcSplat[i], q.r);
    atomicAdd(lcSplat[i + 1], q.g);
    atomicAdd(lcSplat[i + 2], q.b);
    atomicAdd(lcSplat[i + 3], q.a);
}
#endif

#ifdef LC_SAMPLE
uniform sampler3D lcCSampler;   // remembered colour, ping-pong by frame: rgb sum, a weight
uniform sampler3D lcDSampler;
uniform vec3 eyePosition;
uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

// colour of a held light (item.properties): 101 soul, 102 redstone, 103 copper; any other light, a plain torch
vec3 heldLightHue(int id) {
    return id == 101 ? vec3(0.38, 0.98, 1.0) : (id == 102 ? vec3(1.0, 0.2, 0.15) : (id == 103 ? vec3(0.6, 1.0, 0.6) : LC_TORCH_HUE));
}

// block light level raised by a light in the player's hands (HAND_LIGHT): as the block light around a torch, one level
// less per block from the player's eye; hue: the light that wins there
float handLight(vec3 playerPos, out vec3 hue) {
    hue = LC_TORCH_HUE;
    #ifdef HAND_LIGHT
        if (heldBlockLightValue + heldBlockLightValue2 == 0) return 0.0;   // uniform: nothing lit in the hands
        float d = length(playerPos - (eyePosition - cameraPosition));
        float main = float(heldBlockLightValue) - d, off = float(heldBlockLightValue2) - d;
        hue = main >= off ? heldLightHue(heldItemId) : heldLightHue(heldItemId2);
        return saturate(max(main, off) / 15.0);
    #else
        return 0.0;
    #endif
}

// colour the block light takes at a point: rgb the hue of the lights around (brightest channel 1), a how much of it
// (0 where they are plain torches, whose light the block light colour already is, or none are known)
vec4 blockLightHue(vec3 playerPos, float handLevel, vec3 handHue, float blockLevel) {
    vec3 hue = LC_TORCH_HUE;
    float confidence = 0.0;
    #ifdef COLORED_LIGHT
        vec3 p = (playerPos + cameraPosition) / LC_CELL - vec3(lcOrigin(cameraPosition));
        vec3 edge = min(p, vec3(LC_GRID) - p);
        if (all(greaterThan(edge, vec3(0.5)))) {
            vec4 v;   // a uniform branch: one read
            if ((frameCounter & 1) == 0) v = texture(lcCSampler, p / vec3(LC_GRID));
            else v = texture(lcDSampler, p / vec3(LC_GRID));
            if (v.a > 1e-4) {
                hue = v.rgb / v.a;
                confidence = smoothstep(0.002, 0.05, v.a) * saturate(min(edge.x, min(edge.y, edge.z)) / 4.0);
            }
        }
    #endif
    // a held light that is brighter here than the placed ones gives its own colour
    if (handLevel > blockLevel) { hue = handHue; confidence = 1.0; }
    hue /= max(hue.r, max(hue.g, hue.b));
    // warm lights (torches, lanterns, fire, glowstone, lamps: within 0.25 of the torch) keep the block light as it is
    float colourful = smoothstep(0.25, 0.4, distance(hue, LC_TORCH_HUE));
    return vec4(hue, confidence * colourful);
}
#endif
#endif
