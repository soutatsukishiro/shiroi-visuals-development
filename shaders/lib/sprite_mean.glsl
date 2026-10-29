#ifndef SPRITE_MEAN_GLSL
#define SPRITE_MEAN_GLSL
// Kept apart from lib/surface.glsl (whose derivative functions only compile in a fragment stage) so that a vertex
// stage can read it too (program/gbuffers_translucent.glsl).
#include "/lib/common.glsl"

// mean luminance and saturation (sRGB) of a block's sprite, from 4 x 4 texels spread over it
vec2 spriteMeanLumSat(sampler2D tex, vec2 midUv, vec2 halfUv) {
    vec2 size = vec2(textureSize(tex, 0));
    ivec2 lo = ivec2(floor((midUv - halfUv) * size + 0.5));
    ivec2 sz = max(ivec2(floor(halfUv * 2.0 * size + 0.5)), ivec2(1));
    vec3 acc = vec3(0.0);
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
        vec4 c = texelFetch(tex, lo + (ivec2(i, j) * 2 + 1) * sz / 8, 0);
        if (c.a < 0.1) continue;
        float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
        acc += vec3(luminance(c.rgb), mx > 0.0 ? (mx - mn) / mx : 0.0, 1.0);
    }
    return acc.z > 0.0 ? acc.xy / acc.z : vec2(0.5, 0.0);
}
#endif
