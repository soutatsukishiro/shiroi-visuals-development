#ifndef SKYPROBE_GLSL
#define SKYPROBE_GLSL
// Sky probe: the analytic sky rendered into an octahedral environment map [Engelhardt & Dachsbacher 2008; Cigolle
// et al. 2014] with pre-filtered GGX levels for glossy reflections (split-sum approximation, Karis 2013) and one
// texel of hemispherical irradiance for the ambient light. Everything lives in colortex14 (256 x 128):
//   level 0: 128x128 at (0,0)  level 1: 64x64 at (128,0)  level 2: 32x32 at (192,0)  level 3: 16x16 at (224,0)
//   level 4: 8x8 at (240,0)    levels 5..7: 8x8 at (128 + 8k, 64)  irradiance: texel (255,127)
// The octahedral axis is world up, so the fold seams stay in the lower hemisphere.
#include "/lib/common.glsl"
#include "/lib/look.glsl"

const int PROBE_LEVELS = 8;
const ivec2 PROBE_IRRADIANCE_TEXEL = ivec2(255, 127);
const float SKY_IRRADIANCE_GAIN = SKY_AMBIENT_MUL;

ivec4 probeLevelRect(int level) {
    if (level == 0) return ivec4(0, 0, 128, 128);
    if (level == 1) return ivec4(128, 0, 64, 64);
    if (level == 2) return ivec4(192, 0, 32, 32);
    if (level == 3) return ivec4(224, 0, 16, 16);
    if (level == 4) return ivec4(240, 0, 8, 8);
    return ivec4(128 + 8 * (level - 5), 64, 8, 8);
}

vec2 probeDirToUv(vec3 d) { return octEncode(normalize(d.xzy)) * 0.5 + 0.5; }
vec3 probeUvToDir(vec2 uv) { return octDecode(uv * 2.0 - 1.0).xzy; }

#ifdef PROBE_SAMPLER
// bilinear inside one level's rectangle (clamped to it, so neighbouring levels never bleed in)
vec3 probeFetchLevel(sampler2D probe, vec3 dir, int level) {
    ivec4 r = probeLevelRect(level);
    vec2 p = probeDirToUv(dir) * vec2(r.zw) - 0.5;
    ivec2 i0 = ivec2(floor(p));
    vec2 f = fract(p);
    ivec2 lo = r.xy, hi = r.xy + r.zw - 1;
    vec3 a = texelFetch(probe, clamp(r.xy + i0, lo, hi), 0).rgb;
    vec3 b = texelFetch(probe, clamp(r.xy + i0 + ivec2(1, 0), lo, hi), 0).rgb;
    vec3 c = texelFetch(probe, clamp(r.xy + i0 + ivec2(0, 1), lo, hi), 0).rgb;
    vec3 d = texelFetch(probe, clamp(r.xy + i0 + ivec2(1, 1), lo, hi), 0).rgb;
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
// between two pre-filtered levels
vec3 probeSample(sampler2D probe, vec3 dir, float level) {
    level = clamp(level, 0.0, float(PROBE_LEVELS - 1));
    int l0 = int(floor(level));
    return mix(probeFetchLevel(probe, dir, l0), probeFetchLevel(probe, dir, min(l0 + 1, PROBE_LEVELS - 1)), fract(level));
}
vec3 probeIrradiance(sampler2D probe) { return texelFetch(probe, PROBE_IRRADIANCE_TEXEL, 0).rgb; }
#endif

// level of a roughness: levels are pre-filtered for roughness l / (N - 1) of the glossiness curve 1 - (1 - r)^2
float probeLevel(float roughness) {
    float gloss = 1.0 - roughness;
    return float(PROBE_LEVELS - 1) * (1.0 - gloss * gloss);
}
// the probe holds the open sky: surfaces with little sky light (under trees, in caves) fade it out
float probeSkyFade(float skyLevel01) {
    float level = skyLevel01 * 15.0 * (16.0 / 15.0);
    float f = saturate((level - PROBE_SKY_FADE.x) / max(PROBE_SKY_FADE.y - PROBE_SKY_FADE.x, 1.0));
    return f * f * f;
}

#endif
