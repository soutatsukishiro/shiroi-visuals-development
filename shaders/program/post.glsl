// HDR post chain:
//  LE_DOWN      1/8 resolution gaussian of log luminance (colortex15): the coarse "base" layer of local exposure,
//               computed by program/le_down.glsl (the same pass's compute shader) and copied here
//  LE_APPLY     optional TAA, then local exposure: base / detail decomposition [Durand & Dorsey 2002] where the
//               base is the bilateral grid [Chen et al. 2007] mixed with the gaussian; the base is pulled towards the
//               average luminance by LOCAL_EXPOSURE_STRENGTH, the detail is kept. Also stores the frame for next
//               frame's reflections (colortex6).
//  BLOOM_DOWN   dual filter downsample [Bjorge 2015, "Bandwidth-Efficient Rendering"]: centre 1/2 + four diagonal
//               taps 1/8; the first level carries the emissive share of the luminance in alpha
//  BLOOM_UP     dual filter upsample: eight diagonal taps (1/6 at 2 texels, 1/12 at 4 texels) of the level below,
//               plus the emissive share of this level (tight glow of light sources)
//  BLOOM_BLEND  last upsample added to the frame
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
#ifdef TAA
flat out vec2 vRasterOffset;
#endif
void main() {
    gl_Position = ftransform();
    #ifdef TAA
        vRasterOffset = taaJitterPixels() / sceneSize();
    #endif
    #ifdef CELESTIAL_ONLY
        // Keep the existing integer-sized region and pixel coordinates; avoid
        // rasterizing the rest of the full-size reusable attachment.
        vec2 frameSize = vec2(viewWidth, viewHeight);
        vec2 activeSize = max(floor(frameSize * CELESTIAL_SCALE), vec2(1.0));
        gl_Position.xy = (gl_Position.xy + gl_Position.w) * (activeSize / frameSize) - gl_Position.w;
    #endif
}
#endif

#ifdef FRAGMENT_SHADER
#ifdef TAA
flat in vec2 vRasterOffset;
#endif
#include "/lib/exposure.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex2;   // after deferred: emissive glow weight
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex15;
uniform sampler3D gridImgSampler;

vec2 screenSize() { return vec2(viewWidth, viewHeight); }
// The colour after composite11 is on the stable output grid. Metadata still
// belongs to the jittered raster grid: use the same current-frame footprint.
vec4 stableGlowMetadata(vec2 uv) {
    #ifdef TAA
        vec2 halfPixel = 0.5 / sceneSize();
        return texture(colortex2, sceneUv(clamp(uv + vRasterOffset, halfPixel, vec2(1.0) - halfPixel)));
    #else
        return texture(colortex2, uv);
    #endif
}
// Reuse HDR targets whose geometry/SSR work finished before bloom. Each holds
// a top-left reduced-resolution celestial level; scene bloom stays independent.
uniform sampler2D colortex1;
uniform sampler2D colortex5;
uniform sampler2D colortex7;
vec3 celestialLevel(sampler2D src, vec2 uv, float scale) {
    vec2 size = max(floor(screenSize() * scale), vec2(1.0));
    vec2 lo = 0.5 / screenSize();
    vec2 hi = (size - 0.5) / screenSize();
    return texture(src, clamp(uv * size / screenSize(), lo, hi)).rgb;
}
// Separable Gaussian in screen-height units: the glow keeps its reach at
// different resolutions, rather than shrinking to a thin rim at 1080p/4K.
vec3 celestialSoftBlur(sampler2D src, vec2 uv, float scale, vec2 axis) {
    vec2 stepUv = axis * vec2(viewHeight / viewWidth, 1.0) * 0.0125;
    vec3 sum = vec3(0.0);
    float total = 0.0;
    for (int i = -6; i <= 6; ++i) {
        float weight = exp(-0.125 * float(i * i));
        sum += celestialLevel(src, uv + stepUv * float(i), scale) * weight;
        total += weight;
    }
    return sum / total;
}

vec3 celestialUpsample(sampler2D src, vec2 uv, float scale) {
    vec2 h = 0.5 / max(floor(screenSize() * scale), vec2(1.0));
    vec3 acc = vec3(0.0);
    acc += celestialLevel(src, uv + h * vec2(2,2), scale) * 0.166;
    acc += celestialLevel(src, uv + h * vec2(-2,2), scale) * 0.166;
    acc += celestialLevel(src, uv + h * vec2(2,-2), scale) * 0.166;
    acc += celestialLevel(src, uv + h * vec2(-2,-2), scale) * 0.166;
    acc += celestialLevel(src, uv + h * vec2(4,4), scale) * 0.083;
    acc += celestialLevel(src, uv + h * vec2(-4,4), scale) * 0.083;
    acc += celestialLevel(src, uv + h * vec2(4,-4), scale) * 0.083;
    acc += celestialLevel(src, uv + h * vec2(-4,-4), scale) * 0.083;
    return acc;
}

float logRangeNorm(float lumLog) { return (lumLog - LUM_RANGE.x) / (LUM_RANGE.y - LUM_RANGE.x); }

#ifdef LE_DOWN
/* RENDERTARGETS: 15 */
layout(location = 0) out vec4 outLog;
uniform sampler2D leDownSampler;
void main() {
    outLog = vec4(texelFetch(leDownSampler, ivec2(gl_FragCoord.xy), 0).r, 0.0, 0.0, 1.0);
}
#endif

#ifdef LE_APPLY
uniform sampler2D colortex6;
uniform sampler2D colortex3;   // z: material id (MAT_OUTLINE under the block outline)
uniform sampler2D depthtex0;
/* RENDERTARGETS: 0,6 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outPrev;

// trilinear read of the filtered bilateral grid: x = weight, y = weighted normalised log luminance
vec2 gridLookup(vec3 p) {
    vec3 q = p * vec3(GRID_DIM) - 0.5;
    ivec3 i0 = ivec3(floor(q));
    vec3 f = q - vec3(i0);
    vec2 r = vec2(0.0);
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, k >> 2);
        vec3 w = mix(1.0 - f, f, vec3(o));
        r += texelFetch(gridImgSampler, clamp(i0 + o, ivec3(0), GRID_DIM - 1), 0).xy * (w.x * w.y * w.z);
    }
    return r;
}

#include "/lib/motion.glsl"
#ifdef ENTITY_MOTION
uniform sampler2D colortex4;   // entity screen motion (lib/entitymotion.glsl)
#endif
// per-pixel TAA state (phase hold run, frames still), ping-pong (lib/taa.glsl)
writeonly uniform image2D taaFlickA;
writeonly uniform image2D taaFlickB;
uniform sampler2D taaFlickASampler;
uniform sampler2D taaFlickBSampler;
#include "/lib/taa.glsl"

void main() {
    vec2 uv = gl_FragCoord.xy / screenSize();
    vec3 col = sanitize(texture(colortex0, sceneUv(uv)).rgb);
    vec3 history = col;
    float historyDepth = 0.0;
    #ifdef TAA
        history = temporalResolve(uv, col, col, historyDepth);
    #endif
    #ifdef LOCAL_EXPOSURE
        float lumLog = log2(clamp(luminance(col), LUM_RANGE.z, LUM_RANGE.w));
        vec2 g = gridLookup(vec3(uv, logRangeNorm(lumLog)));
        float gridLog = (g.y / max(g.x, 1e-6)) * (LUM_RANGE.y - LUM_RANGE.x) + LUM_RANGE.x;
        float blurLog = texture(colortex15, uv).r;
        float baseLog = g.x < 0.001 ? blurLog : mix(gridLog, blurLog, 0.5);
        float avgLog = log2(clamp(sceneAverageLuminance(), LUM_RANGE.z, LUM_RANGE.w));
        // base pulled towards the average, detail (lumLog - baseLog) kept as it is
        float targetLog = (lumLog - baseLog) + (1.0 - LOCAL_EXPOSURE_STRENGTH) * (baseLog - avgLog) + avgLog;
        col *= exp2(targetLog - lumLog);
    #endif
    // outputs written in location order (Vitrail numbers them by first write)
    outColor = vec4(col, 1.0);
    outPrev = vec4(history, historyDepth);
}
#endif

#ifdef BLOOM_DOWN
layout(location = 0) out vec4 outBloom;
void main() {
    vec2 dstSize = max(floor(screenSize() * BLOOM_SCALE), vec2(1.0));
    vec2 srcSize = max(floor(screenSize() * BLOOM_SCALE * 2.0), vec2(1.0));
    vec2 uv = gl_FragCoord.xy / dstSize;
    vec2 h = 1.0 / srcSize;
    vec2 maxUv = (srcSize - 0.5) / srcSize;
    #ifdef BLOOM_FIRST
        // the HDR frame above the threshold; alpha: the part of its luminance that is emissive (colortex2.x after
        // deferred: emissive surfaces, eyes layers, lit particles)
        float threshold = sceneAverageLuminance() * BLOOM_THRESHOLD;
        #define TAP(o) { vec2 p = min(uv + (o), maxUv); vec3 c = texture(BLOOM_SRC, p).rgb; c *= step(threshold, luminance(c)); acc += vec4(c, luminance(c) * clamp(stableGlowMetadata(p).x * GLOW_WEIGHT_RANGE, 0.0, GLOW_WEIGHT_RANGE)) * w; }
    #else
        #define TAP(o) { acc += texture(BLOOM_SRC, min(uv + (o), maxUv)) * w; }
    #endif
    vec4 acc = vec4(0.0);
    float w = 0.5;   TAP(vec2(0.0))
    w = 0.125;       TAP(vec2(h.x, h.y)) TAP(vec2(-h.x, -h.y)) TAP(vec2(-h.x, h.y)) TAP(vec2(h.x, -h.y))
    outBloom = acc;
}
#endif

// eight diagonal taps of a lower level: 1/6 at 2 texels, 1/12 at 4 texels (h = half a texel of that level)
vec3 dualUpsample(sampler2D src, vec2 uv, vec2 h, vec2 maxUv) {
    vec3 acc = vec3(0.0);
    acc += texture(src, min(uv + h * vec2(2.0, 2.0), maxUv)).rgb * 0.166;
    acc += texture(src, min(uv + h * vec2(-2.0, 2.0), maxUv)).rgb * 0.166;
    acc += texture(src, min(uv + h * vec2(2.0, -2.0), maxUv)).rgb * 0.166;
    acc += texture(src, min(uv + h * vec2(-2.0, -2.0), maxUv)).rgb * 0.166;
    acc += texture(src, min(uv + h * vec2(4.0, 4.0), maxUv)).rgb * 0.083;
    acc += texture(src, min(uv + h * vec2(-4.0, -4.0), maxUv)).rgb * 0.083;
    acc += texture(src, min(uv + h * vec2(-4.0, 4.0), maxUv)).rgb * 0.083;
    acc += texture(src, min(uv + h * vec2(4.0, -4.0), maxUv)).rgb * 0.083;
    return acc;
}

#ifdef BLOOM_UP
layout(location = 0) out vec4 outBloom;
void main() {
    vec2 dstSize = max(floor(screenSize() * BLOOM_SCALE), vec2(1.0));
    vec2 srcSize = max(floor(screenSize() * BLOOM_SCALE * 0.5), vec2(1.0));
    vec2 uv = gl_FragCoord.xy / dstSize;
    vec3 acc = dualUpsample(BLOOM_SRC, uv, 0.5 / srcSize, (srcSize - 0.5) / srcSize);
    #ifdef BLOOM_SELF
        // the emissive share of this level's own downsample (Iris flips the target, so this reads the down pass
        // result): light sources get a tight glow, everything else only the wide haze of the lower levels
        vec4 own = texture(BLOOM_SELF, uv);
        acc += own.rgb * clamp(own.a / max(luminance(own.rgb), 1e-6), 0.0, GLOW_WEIGHT_RANGE) * EMISSIVE_BLOOM;
    #endif
    outBloom = vec4(acc, 0.0);
}
#endif

#ifdef BLOOM_BLEND
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;
void main() {
    vec2 uv = gl_FragCoord.xy / screenSize();
    vec2 srcSize = max(floor(screenSize() * 0.5), vec2(1.0));
    vec3 hdr = texture(colortex0, uv).rgb;
    #ifdef BLOOM
        hdr += dualUpsample(colortex8, uv, 0.5 / srcSize, (srcSize - 0.5) / srcSize) * BLOOM_INTENSITY;
    #endif
    outColor = vec4(hdr, 1.0);
}
#endif

#ifdef CELESTIAL_ONLY
layout(location = 0) out vec4 outCelestial;
void main() {
    vec2 size = max(floor(screenSize() * CELESTIAL_SCALE), vec2(1.0));
    if (any(greaterThanEqual(gl_FragCoord.xy, size))) discard;
    vec2 uv = gl_FragCoord.xy / size;
    vec3 extra = vec3(0.0);
    #if defined BLOOM && SUN_LIGHT_BLEED == 1
        #ifdef CELESTIAL_DOWN
            vec2 h = 1.0 / max(floor(screenSize() * CELESTIAL_SCALE * 2.0), vec2(1.0));
            for (int i = 0; i < 5; ++i) {
                vec2 offset = i == 0 ? vec2(0.0) : vec2((i == 1 || i == 4) ? 1.0 : -1.0, i <= 2 ? 1.0 : -1.0);
                vec2 p = clamp(uv + offset * h, h * 0.5, vec2(1.0) - h * 0.5);
                vec3 tap;
                #ifdef CELESTIAL_FIRST
                    // away from the sun and moon the source weight is 0 and the tap would be multiplied by 0: skip the
                    // colour read there (the colour is finite and non-negative, the sum is the same)
                    float boost = stableGlowMetadata(p).a * SUN_GLOW_STRENGTH;
                    tap = vec3(0.0);
                    if (boost != 0.0) {
                        tap = texture(colortex0, p).rgb;
                        tap *= step(sceneAverageLuminance() * BLOOM_THRESHOLD, luminance(tap));
                        tap *= boost * (1.0 + 2.0 * boost);
                    }
                #else
                    tap = celestialLevel(CELESTIAL_SRC, p, CELESTIAL_SCALE * 2.0);
                #endif
                extra += tap * (i == 0 ? 0.5 : 0.125);
            }
        #else
            #ifdef CELESTIAL_BASE
                extra = celestialSoftBlur(CELESTIAL_SELF, uv, CELESTIAL_SCALE, vec2(1.0, 0.0)) * (1.0 + 2.5 * EMISSIVE_BLOOM);
            #else
                // A small tight component anchors the glow without outlining the actor.
                extra = celestialLevel(CELESTIAL_SELF, uv, CELESTIAL_SCALE) * (0.12 * EMISSIVE_BLOOM);
                #ifdef CELESTIAL_WIDE_Y
                    extra += celestialSoftBlur(CELESTIAL_SRC, uv, CELESTIAL_SCALE * 0.5, vec2(0.0, 1.0));
                #else
                    extra += celestialUpsample(CELESTIAL_SRC, uv, CELESTIAL_SCALE * 0.5);
                #endif
            #endif
        #endif
    #endif
    outCelestial = vec4(extra, 0.0);
}
#endif
#ifdef CELESTIAL_BLEND
uniform sampler2D celestialASampler;
uniform sampler2D celestialBSampler;
layout(location = 0) out vec4 outCelestial;
void main() {
    vec2 uv = gl_FragCoord.xy / screenSize();
    vec3 hdr = texture(colortex0, uv).rgb;
    #if defined BLOOM && SUN_LIGHT_BLEED == 1
        // Preserve the original disc, including its existing general bloom.
        #ifdef TAA
            // with the jitter the raw mask flickers at the disc's edge: use the accumulated share of disc
            // (program/celestial_history.glsl, composite12.csh), 1 on the disc, 0 around it
            float discShare = (frameCounter & 1) == 0 ? texture(celestialASampler, uv).r : texture(celestialBSampler, uv).r;
            // ... and only where the colour is the disc's: the TAA averages an edge in a compressed scale, so a pixel
            // that is mostly disc by its samples can still look nearly as dark as the arm or sky beside it; kept
            // without the glow it was darker than both neighbours, a thin dark line along the disc
            float centreLum = luminance(hdr), peakLum = centreLum;
            for (int k = 0; k < 4; ++k) {
                vec2 o = vec2(k == 0 ? 1.0 : (k == 1 ? -1.0 : 0.0), k == 2 ? 1.0 : (k == 3 ? -1.0 : 0.0));
                peakLum = max(peakLum, luminance(texture(colortex0, uv + o / screenSize()).rgb));
            }
            float discLike = smoothstep(0.3, 0.7, centreLum / max(peakLum, 1e-6));
            hdr += celestialUpsample(colortex1, uv, 0.5) * BLOOM_INTENSITY * (1.0 - saturate(discShare) * discLike);
        #else
            float sourceCoverage = texelFetch(colortex2, ivec2(gl_FragCoord.xy), 0).a;
            if (sourceCoverage <= 0.0)
                hdr += celestialUpsample(colortex1, uv, 0.5) * BLOOM_INTENSITY;
        #endif
    #endif
    outCelestial = vec4(hdr, 1.0);
}
#endif
#endif
