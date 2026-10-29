#ifndef EXPOSURE_GLSL
#define EXPOSURE_GLSL
// Automatic exposure and local exposure state, shared by the exposure passes and the post chain.
//  * global: a centre-weighted log-luminance histogram; the average of the brightest part of it (percentiles) is
//    approached exponentially over time (eye adaptation)
//  * local: a bilateral grid of log luminance [Chen, Paris & Durand 2007] over screen x, y and luminance, used to
//    compress the dynamic range locally (program/post.glsl, LE_APPLY)
#include "/lib/common.glsl"
#include "/lib/look.glsl"

const float CENTRE_WEIGHT = 1.0;            // falloff of the centre weighting, exp(-d^2 * CENTRE_WEIGHT)
const ivec3 GRID_DIM = ivec3(64, 36, 16);    // bilateral grid: x, y cells and luminance slices
// 64 x 36 x 16, written out: it sizes an array, and Vitrail's translator drops `const` from any initialiser that is
// not made of literals only, after which the array size is no longer a constant expression
const int GRID_CELLS = 36864;
const vec4 LUM_RANGE = vec4(-3.0, 17.0, 0.125, 131072.0);   // grid luminance range: log2 min, log2 max, min, max

layout(std430, binding = 0) buffer ExposureState {
    uint histogram[256];      // bin 0: too dark to count
    float avgLum;             // adapted average luminance
    float targetLum;          // this frame's average
    float duskFloor;          // lower limit of the exposure average around sunset and sunrise (EXP_AVERAGE)
    float pad1;
    uint grid[GRID_CELLS * 2];// per cell: weight, weighted log luminance (fixed point, x256)
} exposureState;

float sceneAverageLuminance() { float a = exposureState.avgLum; return (a > 0.0 && a < 1e6) ? a : 1.0; }
// radiance that shows as a value of 1 on screen at the current exposure (without the EV offset): for overlays that
// vanilla adds on screen, like the enchantment glint
float screenScale() {
    #ifdef AUTO_EXPOSURE
        return clamp(sceneAverageLuminance(), EXPOSURE_AVG_CLAMP.x, EXPOSURE_AVG_CLAMP.y) / 0.18;
    #else
        return 1.0;
    #endif
}

// The enchantment glint of an item drawn in one pass with it (MC 26 draws glinted items that way; Iris then gives the
// pack mc_hasGlint / mc_sampleGlint when it defines IRIS_INLINE_GLINT). Vanilla adds the glint's square to the colour
// on screen, after the display gamma; here that screen value is turned into light (display gamma 2.2) and scaled to the
// exposure, compensation included, so the moving shine shows as in vanilla by day and at night and its brightest
// streaks take the bloom. (Added as it is, before the gamma, even the dark part of the glint texture lifted the item
// to a flat purple.)
vec3 glintRadiance(vec3 glint) {
    return srgbToLinear(glint * glint) * GLINT_STRENGTH * screenScale() * exp2(-EXPOSURE_EV);
}

float duskExposureFloor() { float f = exposureState.duskFloor; return (f > 0.0 && f < 1e6) ? f : 0.0; }

#endif
