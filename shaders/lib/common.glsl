#ifndef COMMON_GLSL
#define COMMON_GLSL
// Shared by every program: user settings, the Iris uniforms in use, constants, small math helpers, colour and
// normal encodings, space conversions, material ids.

#include "/lib/settings.glsl"

// ------------------------------------------------------------------ Iris uniforms
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform float sunAngle;
uniform int frameCounter;
uniform float frameTime;
uniform float frameTimeCounter;
uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;
uniform float rainStrength;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform float nightVision;

// custom uniforms (shaders.properties), 0..1, smoothed: the player is in a pale garden / where precipitation is snow
uniform float paleGardenWeight;
uniform float snowWeight;
// biome look (shaders.properties, R14): air media, weather fog, sulfur caves, Nether atmospheres; biomeLookReady is 1
// when the custom uniforms loaded
uniform float biomeLookReady;
uniform float biomeFogDensity, biomeFogScatter, biomeFogAbsR, biomeFogAbsG, biomeFogAbsB, biomeFogG;
uniform float precipitationWeight;
uniform float sulfurCavesWeight;
uniform float netherSkyR, netherSkyG, netherSkyB, netherRayleigh;

// ------------------------------------------------------------------ constants
const float PI = 3.14159274;
const float INV_PI = 0.318309873;
const float INV_4PI = 0.07957747;

// Iris shadow pass (one shadow map holding the 2x2 cascade atlas of lib/shadowmap.glsl)
const int shadowMapResolution = 4096; // [2048 4096 8192]
const float shadowDistance = 128.0;
const float shadowIntervalSize = 2.0;
const bool shadowHardwareFiltering = false;
const float shadowDistanceRenderMul = 1.0;
const float sunPathRotation = 0.0;
const float ambientOcclusionLevel = 1.0;

// VITRAIL_EDITION: build.py replaces this line with "#define SHIROI_VITRAIL_SINGLE_CASCADE 1" in the Vitrail ZIP

// Shadow pass without a geometry stage. Vitrail (Minecraft's Vulkan renderer) runs no geometry shader that emits more
// than the triangle it receives, so the cascades cannot be drawn in one pass there; the map then holds a single
// cascade. Iris, of any version, always keeps the cascades: it defines IRIS_FEATURE_<flag> only for the flags a pack
// lists in iris.features.optional (this one lists TESSELLATION_SHADERS only), while Vitrail defines every flag it
// serves, BLOCK_EMISSION_ATTRIBUTE among them, and never TESSELLATION_SHADERS.
// The Vitrail edition has no shadow geometry stage at all (build.py leaves the .gsh files out): it keeps the
// single-cascade path and receiver math, compiled directly from shadow.vsh to shadow.fsh.
#ifdef SHIROI_VITRAIL_SINGLE_CASCADE
    #define SHADOW_SINGLE_PASS
#elif defined IRIS_FEATURE_BLOCK_EMISSION_ATTRIBUTE && !defined IRIS_FEATURE_TESSELLATION_SHADERS
    #define SHADOW_SINGLE_PASS
#endif

// Internal raster region inside engine-owned native-sized attachments.
// History, post-TAA colour, bloom, probe and shadow targets keep their own grids.
#if RENDER_SCALE == 85 && defined TAA
    #define SHIROI_UPSCALE
#endif
vec2 sceneSize() {
    #ifdef SHIROI_UPSCALE
        return max(floor(vec2(viewWidth, viewHeight) * 0.85), vec2(1.0));
    #else
        return vec2(viewWidth, viewHeight);
    #endif
}
vec2 sceneUv(vec2 uv) {
    #ifdef SHIROI_UPSCALE
        return clamp(uv * sceneSize(), vec2(0.5), sceneSize() - 0.5) / vec2(viewWidth, viewHeight);
    #else
        return uv;
    #endif
}
vec4 sceneClip(vec4 clip) {
    #ifdef SHIROI_UPSCALE
        clip.xy = (clip.xy + clip.w) * (sceneSize() / vec2(viewWidth, viewHeight)) - clip.w;
    #endif
    return clip;
}
#ifdef FRAGMENT_SHADER
void sceneGuard() {
    #ifdef SHIROI_UPSCALE
        if (any(greaterThanEqual(gl_FragCoord.xy, sceneSize()))) discard;
    #endif
}
#endif

// ------------------------------------------------------------------ math helpers
float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }
vec4 saturate(vec4 x) { return clamp(x, 0.0, 1.0); }
float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }   // Rec. 709 weights
// guard against NaN / Inf: one bad pixel would otherwise spread through the bloom and the exposure histogram
vec3 sanitize(vec3 c) { return (any(isnan(c)) || any(isinf(c))) ? vec3(0.0) : max(c, 0.0); }
float smoothstep01(float x) { return x * x * (3.0 - 2.0 * x); }
float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

// display gamma 2.2 (a pure power curve, not the piecewise sRGB function)
vec3 srgbToLinear(vec3 c) { return pow(max(c, 0.0), vec3(2.2)); }
vec3 linearToSrgb(vec3 c) { return pow(max(c, 0.0), vec3(1.0 / 2.2)); }

// octahedral unit-vector encoding [Cigolle et al. 2014, "A Survey of Efficient Representations for Independent
// Unit Vectors"]: project on the octahedron |x| + |y| + |z| = 1, fold the lower half over the upper one
vec2 octEncode(vec3 n) {
    n /= abs(n.x) + abs(n.y) + abs(n.z);
    vec2 sgn = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
    return n.z < 0.0 ? (1.0 - abs(n.yx)) * sgn : n.xy;
}
vec3 octDecode(vec2 e) {
    vec3 n = vec3(e, 1.0 - abs(e.x) - abs(e.y));
    vec2 sgn = vec2(e.x >= 0.0 ? 1.0 : -1.0, e.y >= 0.0 ? 1.0 : -1.0);
    if (n.z < 0.0) n.xy = (1.0 - abs(e.yx)) * sgn;
    return normalize(n);
}

// ------------------------------------------------------------------ spaces
vec3 projectAndDivide(mat4 m, vec3 p) { vec4 h = m * vec4(p, 1.0); return h.xyz / h.w; }
vec3 screenToView(vec2 uv, float depth) { return projectAndDivide(gbufferProjectionInverse, vec3(uv, depth) * 2.0 - 1.0); }
vec3 viewToPlayer(vec3 v) { return mat3(gbufferModelViewInverse) * v + gbufferModelViewInverse[3].xyz; }
vec3 viewToScreen(vec3 v) { return projectAndDivide(gbufferProjection, v) * 0.5 + 0.5; }

// ------------------------------------------------------------------ noise and jitter
// interleaved gradient noise [Jimenez 2014, "Next Generation Post Processing in Call of Duty: Advanced Warfare"]
float interleavedGradientNoise(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }

// TAA sub-pixel jitter: Halton (2, 3), 8 positions, in pixels
float halton(int i, int b) { float f = 1.0, r = 0.0; while (i > 0) { f /= float(b); r += f * float(i % b); i /= b; } return r; }
vec2 taaJitterPixels() {
    #ifdef TAA
        int i = frameCounter % 8 + 1;
        return vec2(halton(i, 2), halton(i, 3)) - 0.5;
    #else
        return vec2(0.0);
    #endif
}
vec4 taaJitterClip(vec4 clip) {
    clip.xy += taaJitterPixels() * 2.0 / sceneSize() * clip.w;
    return sceneClip(clip);
}
// view position of the surface rasterised at this pixel. With TAA the gbuffers draw jittered, so the depth at uv belongs
// to the point at uv - jitter: rebuilt at uv itself it was off by up to half a pixel, a different way every frame, and
// the texel-snapped shadows, caustics and the light along texel edges blinked. The TAA resolve reconstructs
// current colour on a stable grid; SSR reprojects actual jittered ray hits with rasterToView.
vec3 rasterToView(vec2 uv, float depth) { return screenToView(uv - taaJitterPixels() / sceneSize(), depth); }

// Iris lightmap coordinates (1/32 .. 31/32) -> 0..1
vec2 normalizeLightmap(vec2 lm) { return clamp((lm - 1.0 / 32.0) * 16.0 / 15.0, 0.0, 1.0); }

// ------------------------------------------------------------------ material ids (block.properties, colortex3.z * 255)
#define MAT_DEFAULT 0
#define MAT_WATER 1
#define MAT_LEAVES 2
#define MAT_FOLIAGE 3
#define MAT_EMISSIVE_FULL 4
#define MAT_EMISSIVE_TORCH 5
#define MAT_LAVA 6
#define MAT_METAL 7
#define MAT_ORE 8
#define MAT_GEM 9
#define MAT_GLASS 10
#define MAT_POLISHED 11
#define MAT_SNOW 12
#define MAT_ICE 13
#define MAT_SAND 14
#define MAT_WOOD 15
#define MAT_STONE 16
#define MAT_DIRT 17
#define MAT_WOOL 18
#define MAT_NETHER_PORTAL 19
#define MAT_GRASS_BLOCK 20
#define MAT_ORE_GEM 21
#define MAT_OBSIDIAN 22
#define MAT_FARMLAND_WET 23
#define MAT_FARMLAND 24
#define MAT_LEAF_LITTER 25
#define MAT_PETALS 26
#define MAT_MELON 28
#define MAT_PUMPKIN 29
#define MAT_LAST_BLOCK 29    // the highest block material id (block.properties); MOD_COMPAT treats ids above it as unknown
#define MAT_ENTITY 30
#define MAT_HAND 31
#define MAT_PARTICLE 32
#define MAT_EYES 33          // emissive overlays: spider / enderman / phantom eyes, beacon beam
#define MAT_OUTLINE 34       // the block selection outline (gbuffers_line): TAA keeps no history there
#define MAT_CLOUD 40


#ifdef MOD_COMPAT
#include "/lib/mod_compat.glsl"
#endif
#endif
