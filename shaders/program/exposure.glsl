// Exposure compute passes (see lib/exposure.glsl):
//  EXP_BUILD    per pixel: histogram bin (group-local, then the non-empty bins go to the global histogram) and the
//               bilateral grid splat (one pixel out of every 2x2, linear between the two nearest luminance slices)
//  EXP_AVERAGE  one thread: mean bin between the percentiles, then exponential adaptation; clears the histogram
//  EXP_FILTER   gaussian blur of the grid in x, y (radius 2 cells), normalised, into gridImg
//  EXP_CLEAR    clears the grid accumulators for the next frame
// Iris parses workGroups as integer literals only (an expression silently falls back to one group per pixel).
#include "/lib/common.glsl"
#include "/lib/exposure.glsl"
#if defined AUTO_EXPOSURE && !defined DIM_NETHER && !defined DIM_END
#include "/lib/daylight.glsl"
// lower limit of the exposure average around sunset and sunrise (lib/look.glsl DUSK_EXPOSURE_FLOOR), for a view whose
// average is avg; 0 by day and underground (sky light at the camera), the lower clamp by night. Uniforms only, so it is
// worked out here once per frame, for program/final.glsl
float duskExposureFloorFor(float avg) {
    float d = dayPhase();
    float sunLux;
    DAYCURVE(SUN_LUX, d, sunLux)
    float fromNoon = min(d, 1.0 - d);
    float eyeSky = saturate(float(eyeBrightnessSmooth.y) / 240.0);
    float skyFloor = EXPOSURE_AVG_CLAMP.x + DUSK_EXPOSURE_FLOOR.x * pow(max(sunLux, 0.0), DUSK_EXPOSURE_FLOOR.y);
    float skyAverage = DUSK_EXPOSURE_REF.x * pow(max(sunLux, 0.0), DUSK_EXPOSURE_REF.y);
    float floorHere = skyFloor * min(1.0, avg / max(skyAverage, 1e-4));
    return smoothstep(DUSK_EXPOSURE_PHASES.x, DUSK_EXPOSURE_PHASES.y, fromNoon) * eyeSky * floorHere;
}
#endif

#ifdef EXP_BUILD
layout(local_size_x = 16, local_size_y = 16) in;
#ifdef SHIROI_UPSCALE
const vec2 workGroupsRender = vec2(0.85, 0.85);
#else
const vec2 workGroupsRender = vec2(1.0, 1.0);
#endif
uniform sampler2D colortex0;
shared uint groupHistogram[256];
// The grid splats of the group, summed here first and added to the global grid once per touched entry (integer sums:
// the same totals as one global atomic per splat, with far less contention). Window: GROUP_CELLS x GROUP_CELLS cells
// from the group's first cell, all slices; a splat outside it (cells under 6 pixels) goes straight to the global grid.
const int GROUP_CELLS = 4;
shared uint groupGrid[GROUP_CELLS * GROUP_CELLS * 16 * 2];
ivec2 groupBaseCell;
void splat(int slice, ivec2 cell, uint weight, uint value) {
    ivec2 local = cell - groupBaseCell;
    if (all(lessThan(uvec2(local), uvec2(GROUP_CELLS)))) {
        int k = ((slice * GROUP_CELLS + local.y) * GROUP_CELLS + local.x) * 2;
        atomicAdd(groupGrid[k], weight);
        atomicAdd(groupGrid[k + 1], value);
    } else {
        int a = (slice * GRID_DIM.y + cell.y) * GRID_DIM.x + cell.x;
        atomicAdd(exposureState.grid[a * 2], weight);
        atomicAdd(exposureState.grid[a * 2 + 1], value);
    }
}

uint histogramBin(float lum) {
    if (lum < 0.00095) return 0u;   // below the darkest bin
    return min(uint(saturate((log2(lum) - HIST_MIN_LOG2) / HIST_LOG2_RANGE) * 254.0 + 1.0), 255u);
}

void main() {
    uint li = gl_LocalInvocationIndex;
    groupHistogram[li] = 0u;
    for (uint k = li; k < uint(GROUP_CELLS * GROUP_CELLS * 16 * 2); k += 256u) groupGrid[k] = 0u;
    ivec2 size = ivec2(sceneSize());
    groupBaseCell = ivec2((vec2(gl_WorkGroupID.xy * gl_WorkGroupSize.xy) + 0.5) / vec2(size) * vec2(GRID_DIM.xy));
    barrier();
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    if (all(lessThan(px, size))) {
        vec2 uv = (vec2(px) + 0.5) / vec2(size);
        float lum = luminance(texelFetch(colortex0, px, 0).rgb);
        if (isnan(lum) || isinf(lum)) lum = 0.0;
        vec2 fromCentre = uv - 0.5;
        atomicAdd(groupHistogram[histogramBin(lum)], uint(exp(-dot(fromCentre, fromCentre) * CENTRE_WEIGHT) * 256.0));
        if (((px.x | px.y) & 1) == 0) {
            float l = (log2(clamp(lum, LUM_RANGE.z, LUM_RANGE.w)) - LUM_RANGE.x) / (LUM_RANGE.y - LUM_RANGE.x);
            ivec2 cell = ivec2(uv * vec2(GRID_DIM.xy));
            int s0 = clamp(int(l * float(GRID_DIM.z)), 0, GRID_DIM.z - 2);
            float f = saturate(float(GRID_DIM.z) * l - float(s0));
            splat(s0, cell, uint((1.0 - f) * 256.0), uint(l * (1.0 - f) * 256.0));
            splat(s0 + 1, cell, uint(f * 256.0), uint(l * f * 256.0));
        }
    }
    barrier();
    if (groupHistogram[li] != 0u) atomicAdd(exposureState.histogram[li], groupHistogram[li]);
    for (uint k = li; k < uint(GROUP_CELLS * GROUP_CELLS * 16); k += 256u) {
        if (groupGrid[k * 2u] == 0u && groupGrid[k * 2u + 1u] == 0u) continue;
        int x = int(k) % GROUP_CELLS, y = (int(k) / GROUP_CELLS) % GROUP_CELLS, slice = int(k) / (GROUP_CELLS * GROUP_CELLS);
        ivec2 cell = groupBaseCell + ivec2(x, y);
        int a = (slice * GRID_DIM.y + cell.y) * GRID_DIM.x + cell.x;
        atomicAdd(exposureState.grid[a * 2], groupGrid[k * 2u]);
        atomicAdd(exposureState.grid[a * 2 + 1], groupGrid[k * 2u + 1u]);
    }
}
#endif

#ifdef EXP_AVERAGE
layout(local_size_x = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);
void main() {
    const float FIXED = 0.00390625;   // 1 / 256
    float total = 0.0;
    for (int i = 1; i < 256; i++) total += float(exposureState.histogram[i]) * FIXED;
    // mean bin of the weight between the two percentiles
    float from = total * HIST_PERCENTILES.x, to = total * HIST_PERCENTILES.y;
    float below = 0.0, binSum = 0.0, weight = 0.0;
    for (int i = 1; i < 256; i++) {
        float lo = max(from, below);
        below += float(exposureState.histogram[i]) * FIXED;
        float part = max(lo, min(to, below)) - lo;
        binSum += part * float(i);
        weight += part;
    }
    float meanBin = binSum / max(weight, 1.0);
    float targetLog = (meanBin - 1.0) * HIST_LOG2_RANGE * 0.003937008 + HIST_MIN_LOG2;   // 0.003937008 = 1 / 254
    float prev = exposureState.avgLum;
    if (isnan(prev) || isinf(prev) || prev > 1e6) prev = 0.0;
    float prevLog = clamp(log2(max(prev, 0.00095)), HIST_MIN_LOG2, HIST_MIN_LOG2 + HIST_LOG2_RANGE);
    float speed = prevLog < targetLog ? ADAPT_SPEED.x : ADAPT_SPEED.y;
    float k = 1.0 - exp(-ADAPT_RATE * frameTime * speed);
    float adapted = (prev > 0.0 && weight > 0.0) ? prevLog + (targetLog - prevLog) * k : targetLog;
    if (weight <= 0.0) adapted = prevLog;
    exposureState.avgLum = exp2(adapted);
    exposureState.targetLum = exp2(targetLog);
    #if defined AUTO_EXPOSURE && !defined DIM_NETHER && !defined DIM_END
        // from the very average program/final.glsl will use
        exposureState.duskFloor = duskExposureFloorFor(clamp(sceneAverageLuminance(), EXPOSURE_AVG_CLAMP.x, EXPOSURE_AVG_CLAMP.y));
    #else
        exposureState.duskFloor = 0.0;
    #endif
    for (int i = 0; i < 256; i++) exposureState.histogram[i] = 0u;
}
#endif

#ifdef EXP_FILTER
layout(local_size_x = 8, local_size_y = 4, local_size_z = 4) in;
const ivec3 workGroups = ivec3(8, 9, 4);   // GRID_DIM / local size
writeonly uniform image3D gridImg;
void main() {
    ivec3 id = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(id, GRID_DIM))) return;
    const int R = 2;
    float sigma2 = float(R * R) * 0.5;
    vec3 acc = vec3(0.0);
    for (int y = max(id.y - R, 0); y <= min(id.y + R, GRID_DIM.y - 1); y++)
    for (int x = max(id.x - R, 0); x <= min(id.x + R, GRID_DIM.x - 1); x++) {
        int c = (id.z * GRID_DIM.y + y) * GRID_DIM.x + x;
        vec2 v = vec2(float(exposureState.grid[c * 2]), float(exposureState.grid[c * 2 + 1])) * 0.00390625;
        vec2 o = vec2(x - id.x, y - id.y);
        float w = exp(-dot(o, o) / sigma2);
        acc += vec3(v * w, w);
    }
    imageStore(gridImg, id, vec4(acc.xy / max(acc.z, 1e-6), 0.0, 0.0));
}
#endif

#ifdef EXP_CLEAR
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(288, 1, 1);   // GRID_CELLS * 2 / 256
void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i < uint(GRID_CELLS * 2)) exposureState.grid[i] = 0u;
}
#endif
