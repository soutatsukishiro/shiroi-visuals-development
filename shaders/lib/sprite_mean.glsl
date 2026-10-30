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

// the same 4 x 4 texels: mean, darkest and brightest luminance, mean saturation (lib/surface.glsl spriteRelativeRoughness)
vec4 spriteLumStats(sampler2D tex, vec2 midUv, vec2 halfUv) {
    vec2 size = vec2(textureSize(tex, 0));
    ivec2 lo = ivec2(floor((midUv - halfUv) * size + 0.5));
    ivec2 sz = max(ivec2(floor(halfUv * 2.0 * size + 0.5)), ivec2(1));
    vec3 acc = vec3(0.0);
    vec2 range = vec2(1.0, 0.0);
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
        vec4 c = texelFetch(tex, lo + (ivec2(i, j) * 2 + 1) * sz / 8, 0);
        if (c.a < 0.1) continue;
        float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b)), l = luminance(c.rgb);
        acc += vec3(l, mx > 0.0 ? (mx - mn) / mx : 0.0, 1.0);
        range = vec2(min(range.x, l), max(range.y, l));
    }
    return acc.z > 0.0 ? vec4(acc.x / acc.z, range, acc.y / acc.z) : vec4(0.5, 0.0, 1.0, 0.0);
}

#ifdef SPRITE_STATS_CACHE
// spriteLumStats once per sprite rather than once per vertex (16 texel reads at every corner of every leaf cost ~0.9 ms
// in a forest): a table keyed by the sprite's corner in the atlas (bufferObject.6, 8192 slots of 3 uint: key, the
// sprite's centre texel as a signature, the 4 stats in 8 bits each). The signature catches a sprite that moved when the
// resource packs changed. A vertex that finds no matching slot reads the sprite itself and stores it; every writer of a
// key writes the same values, so a race only costs a recomputation. Every path returns the stats as stored (8 bits):
// with full precision where a vertex computed them, the picture depended on which vertex got there first
layout(std430, binding = 6) buffer SpriteStats { uint spriteStats[]; };
const uint SPRITE_STATS_SLOTS = 8192u;

vec4 spriteLumStatsCached(sampler2D tex, vec2 midUv, vec2 halfUv) {
    vec2 size = vec2(textureSize(tex, 0));
    ivec2 lo = ivec2(floor((midUv - halfUv) * size + 0.5));
    uint key = (uint(lo.x) << 16 | (uint(lo.y) & 0xFFFFu)) + 1u;   // 0 marks an empty slot
    uint sig = packUnorm4x8(texelFetch(tex, ivec2(floor(midUv * size)), 0)) | 1u;
    uint h = key * 2654435761u;
    uint slot = (h ^ (h >> 15)) & (SPRITE_STATS_SLOTS - 1u);
    for (int probe = 0; probe < 4; probe++) {
        uint i = ((slot + uint(probe)) & (SPRITE_STATS_SLOTS - 1u)) * 3u;
        uint k = spriteStats[i];
        if (k == key && spriteStats[i + 1u] == sig) return unpackUnorm4x8(spriteStats[i + 2u]);
        if (k == key || (k == 0u && atomicCompSwap(spriteStats[i], 0u, key) == 0u)) {
            uint stats = packUnorm4x8(spriteLumStats(tex, midUv, halfUv));
            spriteStats[i + 2u] = stats;
            spriteStats[i + 1u] = sig;   // last: a reader that sees it also sees the stats (or computes them itself)
            return unpackUnorm4x8(stats);
        }
    }
    return unpackUnorm4x8(packUnorm4x8(spriteLumStats(tex, midUv, halfUv)));   // the 4 slots are taken by other sprites
}
#endif
#endif
