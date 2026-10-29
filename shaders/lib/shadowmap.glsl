#ifndef SHADOWMAP_GLSL
#define SHADOWMAP_GLSL
// Cascaded shadow maps [Engel 2006; Dimitrov 2007] in Iris' single shadow map.
//  * the shadow map is split into a 2x2 atlas, one cascade per tile; shadow.gsh renders each triangle into the
//    tiles that need it (see program/shadow.glsl)
//  * SHADOW_SINGLE_PASS (lib/common.glsl, engines without a geometry stage): one cascade over the whole map
//  * cascade c covers a light-space square of half size CASCADE_EXTENT[c] * SHADOW_RANGE around the camera
//  * receivers: normal offset + slope-scaled depth bias, box PCF of bilinear depth tests, transmission through thin
//    casters for subsurface materials
//  * pixel-art option (TEXEL_SHADOWS): every receiver is moved to the centre of its 1/16 block texel within the
//    surface plane and a single shadow-map texel is read, so each texture texel is either lit or not
//  * cloud shadows: the Java cloud cells projected along the light, box filtered
#include "/lib/common.glsl"
#include "/lib/look.glsl"

const float SHADOW_DEPTH_SPAN = 512.0;   // light-space depth covered by the atlas (+-256 m around the eye plane)
const float LIGHT_ANGLE_FLOOR = 0.2;     // N.L floor of the slope bias (keeps tan finite at grazing light)
// shadow.gsh keeps a triangle in a tile only when it lies entirely inside it, so casters up to one triangle size
// (a block face diagonal) from a tile edge can be missing: receivers stay this far inside
const float TILE_MARGIN = 1.5;
#ifdef SHADOW_SINGLE_PASS
    const float TILE_SIZE = 1.0;   // share of the map side taken by one cascade
#else
    const float TILE_SIZE = 0.5;
#endif

float cascadeExtent(int c) { return CASCADE_EXTENT[c] * SHADOW_RANGE; }
#ifdef SHADOW_SINGLE_PASS
    vec2 cascadeTile(int c) { return vec2(0.0); }
#else
    vec2 cascadeTile(int c) { return vec2(float(c & 1), float(c >> 1)) * 0.5; }
#endif
float cascadeTexel(int c) { return 2.0 / TILE_SIZE * cascadeExtent(c) / float(shadowMapResolution); }   // metres per map texel
int cascadeFilterTaps(int c, float scale) { return clamp(int(CASCADE_FILTER[c] * scale + 0.5), 1, 9); }

// Iris' shadow model-view space: camera centred, 100 m back along the light
// Iris anchors the shadow camera to a world grid of shadowIntervalSize (2 m), and the light is tilted, so each time the
// player crossed a cell the light-space texel grid slid by a fraction of a texel against the world: pixel shadows on
// the blocks around the player flipped on and off while walking. The grid is shifted in light space by s, kept from
// frame to frame (SSBO 2, written by composite24): in the same cell s stays as it is, so the grid turns with the sun
// about the player's cell; on entering another cell s takes the light-space step of the anchor, modulo the coarsest
// cascade texel (the finer ones divide it: extents 1/6, 1/3, 1/2, 1 and 1/4, 1/2, 1), and the texels do not move.
// (V10.4 anchored the grid at the world origin instead: the sun's turning swept it across the blocks at a rate that
// grows with the distance to the origin, shadows trembling everywhere.) Casters (shadow.glsl) and receivers add s.
layout(std430, binding = 2) buffer ShadowGridState {
    vec2 shift;      // s for the cell below
    vec2 cloudStep;  // cloud shadows: x the cloud scroll they use, y the sun step it was taken at (cloudShadowScroll)
    ivec4 cell;      // xyz: the cell, w: 1 once written
} shadowGrid;
// Iris' cell: it snaps with the float remainder (cameraPosition % shadowIntervalSize), which rounds towards zero
ivec3 shadowCell() { return ivec3(trunc(cameraPosition / shadowIntervalSize)); }

// The light turns in steps (SHADOW_SUN_STEP ticks of sun travel). With Iris' continuously turning matrix the whole
// world slides across the shadow-map texel grid every frame (faster the farther from the player), while a caster's
// edge only changes texel in whole steps when it is rasterised: the edge seen on a receiver ran backwards with the
// slide and jumped forwards a texel at a time, and the pixel shadows (a majority over each 1/16 block texel) flipped
// back and forth for seconds before settling. Between steps nothing slides now; at each step the shadows move on by
// the sun's travel. The stepped rotation is built from the stepped angle alone, so it is bit for bit the same on
// every frame of a step (derived from Iris' matrix, which is recomputed every frame, its float noise moved the grid
// by ~1e-5 blocks per frame and flipped texels sitting on a threshold). The light turns about the celestial axis,
// world Z (sunPathRotation is 0): rising in the east (+X) at shadow angle 0, overhead at 0.25. The axes across the
// light are Iris' own (the one of the four right-angle choices closest to its matrix), so the map covers the box Iris
// culls the casters to.
// Casters (shadow.glsl) and receivers use this rotation and the same camera-cell anchor.
uniform float shadowAngle;   // Iris: angle of the shadow light (sun by day, moon by night), 0..0.5 of a turn
float signNonZero(float v) { return v < 0.0 ? -1.0 : 1.0; }
mat3 shadowRotation() {
    mat3 R = mat3(shadowModelView);
    #if SHADOW_SUN_STEP > 0 && !defined DIM_END   // the End's light is the flash, not the sun
        float steps = 24000.0 / float(SHADOW_SUN_STEP);
        float phi = (floor(shadowAngle * steps + 0.5) / steps - 0.25) * 6.28318531;
        vec3 z = vec3(-sin(phi), cos(phi), 0.0);   // towards the light
        vec3 across = vec3(cos(phi), sin(phi), 0.0), axis = vec3(0.0, 0.0, 1.0);
        vec3 irisX = vec3(R[0].x, R[1].x, R[2].x), irisZ = vec3(R[0].z, R[1].z, R[2].z);
        z *= signNonZero(dot(z, irisZ));
        float da = dot(irisX, across), db = dot(irisX, axis);
        vec3 x = abs(da) >= abs(db) ? across * signNonZero(da) : axis * signNonZero(db);
        vec3 y = cross(z, x);
        R = transpose(mat3(x, y, z));
    #endif
    return R;
}
// direction to the light the shadow map is rendered from (player space)
vec3 shadowLightDir() { mat3 R = shadowRotation(); return vec3(R[0].z, R[1].z, R[2].z); }
vec2 shadowGridShift(mat3 R) {
    if (shadowGrid.cell.w == 0) return vec2(0.0);
    vec3 step = vec3(shadowCell() - shadowGrid.cell.xyz) * shadowIntervalSize;   // world move of the anchor
    return mod(shadowGrid.shift + (R * step).xy, cascadeTexel(CASCADES - 1));
}
vec2 shadowGridShift() { return shadowGridShift(shadowRotation()); }
// once per frame, after every shadow lookup (composite24)
void storeShadowGrid() {
    shadowGrid.shift = shadowGridShift();
    shadowGrid.cell = ivec4(shadowCell(), 1);
}
// camera position relative to the corner of its shadow cell: the light-space origin stays on that corner
vec3 shadowAnchorOffset() { return cameraPosition - vec3(shadowCell()) * shadowIntervalSize; }
vec3 shadowSpace(vec3 playerPos, vec2 shift, mat3 R) {
    vec3 ls = R * (playerPos + shadowAnchorOffset());
    return vec3(ls.xy + shift, ls.z);
}
vec3 shadowSpace(vec3 playerPos) { mat3 R = shadowRotation(); return shadowSpace(playerPos, shadowGridShift(R), R); }
vec3 cascadeClip(vec3 ls, int c) { return vec3(ls.xy / cascadeExtent(c), -(ls.z + 100.0) / (SHADOW_DEPTH_SPAN * 0.5)); }

// receivers use cascade c while their shadow-space xy stays within this half size (filter footprint + tile margin)
float cascadeReceiverExtent(int c, float scale) {
    return cascadeExtent(c) - TILE_MARGIN - float(cascadeFilterTaps(c, scale) + 6) * cascadeTexel(c);
}
// casters entirely within this half size are only ever read from the finer cascade (minus the normal offset and the
// filter footprint), so shadow.gsh can skip them in cascade c
float cascadeSkipExtent(int c) {
    return cascadeReceiverExtent(c - 1, 1.0) - 0.5 - float(cascadeFilterTaps(c, 1.0) / 2 + 2) * cascadeTexel(c);
}

#ifndef SHADOWMAP_NO_SAMPLER
uniform sampler2D shadowtex0;

struct ShadowSample { float visibility; float transmission; int cascade; };

// textureGather order: x = (0,1), y = (1,1), z = (1,0), w = (0,0)
float gatherLerp(vec4 v, vec2 f) {
    vec2 rows = mix(v.wx, v.zy, f.x);
    return mix(rows.x, rows.y, f.y);
}
// light that crosses a caster: smooth falloff with the depth below the occluder
vec4 transmissionCurve(vec4 occluderDepth, float receiverDepth, float falloff) {
    vec4 x = saturate(falloff * (receiverDepth - occluderDepth));
    return 1.0 - x * x * (3.0 - 2.0 * x);
}
// weight of texel m (0..n) in an n x n box of bilinear taps one texel apart: inner texels 1, edges 1 - f and f
float boxTapWeight(int m, int n, float f) {
    return (m < n ? 1.0 - f : 0.0) + ((m > 0 && m <= n) ? f : 0.0);
}

// moves a receiver to the centre of its 1/16 block texel, keeping it in the surface plane
vec3 snapToTexelCentre(vec3 playerPos, vec3 normal) {
    const float T = 1.0 / 16.0;
    vec3 n = normalize(normal);
    vec3 toCentre = vec3(T * 0.5) - mod(playerPos + mod(cameraPosition, T), T);
    return playerPos + toCentre - n * dot(toCentre, n);
}

// normal: geometric normal used for the offset (vec3(0): no offset, e.g. volume samples)
ShadowSample shadowLookup(vec3 playerPos, vec3 normal, float filterScale, bool wantTransmission) {
    ShadowSample r = ShadowSample(1.0, 1.0, -1);
    bool hasNormal = dot(normal, normal) > 0.0;
    #ifdef TEXEL_SHADOWS
        if (hasNormal) playerPos = snapToTexelCentre(playerPos, normal);
    #endif
    // the stepped rotation, once per lookup (light direction, grid shift and both transforms use it)
    mat3 shadowR = shadowRotation();
    vec3 toLight = vec3(shadowR[0].z, shadowR[1].z, shadowR[2].z);
    float NdotL = hasNormal ? max(dot(normal, toLight), 0.0) : 1.0;
    // Both transforms use the same snapped grid offset. Calculate it once per lookup instead of once per transform.
    vec2 gridShift = shadowGridShift(shadowR);
    vec3 ls0 = shadowSpace(playerPos, gridShift, shadowR);
    float res = float(shadowMapResolution);
    for (int c = 0; c < CASCADES; c++) {
        if (any(greaterThan(abs(ls0.xy), vec2(cascadeReceiverExtent(c, filterScale)))) || abs(cascadeClip(ls0, c).z) > 1.0) continue;
        // normal offset grows towards grazing light; 1.5 texels of the cascade keep coarse cascades from self-shadowing
        float texel = cascadeTexel(c);
        vec3 clip = cascadeClip(shadowSpace(playerPos + normal * (SHADOW_NORMAL_OFFSET + 1.5 * texel) * (1.0 - NdotL), gridShift, shadowR), c);
        // slope-scaled bias: tan of the light angle, as a fraction of the cascade size, plus one texel of slope
        float ndl = min(max(NdotL, LIGHT_ANGLE_FLOOR), 1.0);
        float tanL = sqrt(1.0 - ndl * ndl) / ndl;
        float bias = (CASCADE_BIAS_SLOPE[c] * tanL + CASCADE_BIAS_CONST[c]) * (2.0 * cascadeExtent(c)) * SHADOW_BIAS_SCALE;
        bias += texel * 0.5 * min(tanL, 4.0) * SHADOW_BIAS_SCALE;
        float receiverDepth = clip.z * 0.5 + 0.5;
        float testDepth = receiverDepth - bias / SHADOW_DEPTH_SPAN;
        vec2 uv = cascadeTile(c) + (clip.xy * 0.5 + 0.5) * TILE_SIZE;
        #ifdef TEXEL_SHADOWS
        if (!hasNormal) {
            // volume samples (no surface, no texel): one map texel, as before
            vec2 lo = cascadeTile(c) + 0.5 / res, hi = cascadeTile(c) + TILE_SIZE - 0.5 / res;
            vec2 p = clamp(uv + 0.5 * ((res * TILE_SIZE) / CASCADE_FILTER_RES[c]) / res, lo, hi);
            vec4 d = textureGather(shadowtex0, p, 0);
            float through = wantTransmission ? gatherLerp(transmissionCurve(d, receiverDepth, SHADOW_DEPTH_SPAN * SSS_FALLOFF), fract(p * res + 0.5)) : 0.0;
            return ShadowSample(step(testDepth, d.w), through, c);
        }
            // The receiver's 1/16 block texel, box filtered by area over the map texels its footprint covers (3 x 3 in
            // the first cascade at 4096). It used to read one map texel: each texel was lit or not, and as the sun
            // moved a long shadow edge crossed whole rows of texels at once, which flipped every few frames (shadows
            // trembling, worst at sunrise and sunset). Now the coverage of the footprint is measured by area and the texel
            // takes the majority: still sharp, one value per texture texel.
            {
                float w = max((1.0 / 16.0) / texel, 1.0);   // footprint side in map texels
                vec2 P = uv * res;
                vec2 b0 = P - 0.5 * w, b1 = P + 0.5 * w;
                vec2 k0 = floor(b0);
                vec2 last = floor(b1 - 1e-4) - k0;
                int span = int(max(last.x, last.y)) + 1;   // texels per side
                int gathers = (span + 1) >> 1;
                float lit = 0.0, through = 0.0, falloff = SHADOW_DEPTH_SPAN * SSS_FALLOFF;
                for (int gy = 0; gy < gathers; gy++) for (int gx = 0; gx < gathers; gx++) {
                    vec2 k = k0 + vec2(float(2 * gx), float(2 * gy));   // lower-left texel of this 2 x 2
                    // overlap of each texel with the box, per axis (texel k covers [k, k + 1))
                    vec2 o0 = clamp(min(b1, k + 1.0) - max(b0, k), 0.0, 1.0);
                    vec2 o1 = clamp(min(b1, k + 2.0) - max(b0, k + 1.0), 0.0, 1.0);
                    vec4 W = vec4(o0.x * o1.y, o1.x * o1.y, o1.x * o0.y, o0.x * o0.y);   // gather order x y z w
                    vec4 d = textureGather(shadowtex0, (k + 1.0) / res, 0);
                    lit += dot(W, step(vec4(testDepth), d));
                    if (wantTransmission) through += dot(W, transmissionCurve(d, receiverDepth, falloff));
                }
                // sharp: the texel is lit when most of its footprint is (a majority over the 3 x 3 map texels instead of
                // one of them: no blur, and a single noisy or acne map texel no longer flips it)
                return ShadowSample(step(0.5, lit / (w * w)), through / (w * w), c);
            }
        #else
        float tapSpacing = (res * TILE_SIZE) / CASCADE_FILTER_RES[c];   // the filter keeps its world size at any resolution
        int taps = cascadeFilterTaps(c, filterScale);
        int halfTaps = taps >> 1;
        float lit = 0.0, through = 0.0;
        float falloff = SHADOW_DEPTH_SPAN * SSS_FALLOFF;
        if (tapSpacing == 1.0) {
            // the taps x taps bilinear box is a weighted sum over (taps + 1)^2 texels: one gather per 2x2 of them
            vec2 P = uv * res;
            vec2 cell = floor(P), f = P - cell;
            vec2 first = cell - float(halfTaps);
            int gathers = (taps + 2) >> 1;
            for (int gy = 0; gy < gathers; gy++) {
                vec2 wy = vec2(boxTapWeight(2 * gy, taps, f.y), boxTapWeight(2 * gy + 1, taps, f.y));
                for (int gx = 0; gx < gathers; gx++) {
                    vec2 wx = vec2(boxTapWeight(2 * gx, taps, f.x), boxTapWeight(2 * gx + 1, taps, f.x));
                    vec4 d = textureGather(shadowtex0, (first + vec2(float(2 * gx), float(2 * gy)) + 1.0) / res, 0);
                    vec4 W = vec4(wx.x * wy.y, wx.y * wy.y, wx.y * wy.x, wx.x * wy.x);
                    lit += dot(W, step(vec4(testDepth), d));
                    if (wantTransmission) through += dot(W, transmissionCurve(d, receiverDepth, falloff));
                }
            }
        } else {
            vec2 lo = cascadeTile(c) + 0.5 / res, hi = cascadeTile(c) + TILE_SIZE - 0.5 / res;
            for (int j = 0; j < taps; j++) for (int i = 0; i < taps; i++) {
                vec2 p = clamp(uv + (vec2(float(i - halfTaps), float(j - halfTaps)) + 0.5) * tapSpacing / res, lo, hi);
                vec4 d = textureGather(shadowtex0, p, 0);
                vec2 f = fract(p * res + 0.5);
                lit += gatherLerp(step(vec4(testDepth), d), f);
                if (wantTransmission) through += gatherLerp(transmissionCurve(d, receiverDepth, falloff), f);
            }
        }
        float n = float(taps * taps);
        return ShadowSample(lit / n, through / n, c);
        #endif
    }
    return r;
}

// past the shadow range everything is lit; the last min(10 %, 8 m) fade smoothly
float shadowRangeFade(float visibility, float viewDepth) {
    float fadeStart = max(SHADOW_RANGE - min(SHADOW_RANGE * 0.1, 8.0), 0.0);
    return mix(visibility, 1.0, smoothstep01(saturate((viewDepth - fadeStart) / (SHADOW_RANGE - fadeStart))));
}
#endif

// ------------------------------------------------------------------ cloud shadows
#ifndef SHADOWMAP_NO_CLOUDS
#include "/lib/clouds.glsl"

// cloud cells (lib/clouds.glsl) seen along the light from the middle of the cloud layer, box filtered over
// CLOUD_SHADOW_FILTER x 0.75 blocks (computed exactly from the cell overlap areas)
// Like the other shadows, the cloud shadow moves in steps (SHADOW_SUN_STEP): it follows the stepped light, not the
// turning sun, and the cloud grid as it was at that light's step. It used to follow both continuously, and its pixel
// edge crept sideways one 1/16 block texel at a time, about ten times a second.
// The cloud scroll is kept from the frame the sun stepped (SSBO 2, written once per frame by storeCloudShadowStep), so the
// whole move happens at once: the sun's step carries the shadow east, the clouds' travel west, and stepped on two clocks
// (R28) the shadow went forward, back and forward again. The sun's pace along the day is eased (not so many ticks per
// step), so the step is taken from the stored state, not computed from the time. With the daylight cycle off the sun
// never steps: then the clouds step alone, every two steps of cloud travel.
#if SHADOW_SUN_STEP > 0 && !defined DIM_END
float cloudSunStep() { return floor(shadowAngle * (24000.0 / float(SHADOW_SUN_STEP)) + 0.5); }
float cloudShadowScroll() {
    float scroll = cloudScroll();
    float moved = mod(scroll - shadowGrid.cloudStep.x + CLOUD_PERIOD * 0.5, CLOUD_PERIOD) - CLOUD_PERIOD * 0.5;
    bool fresh = shadowGrid.cell.w == 0 || shadowGrid.cloudStep.y != cloudSunStep() || abs(moved) >= 0.06 * float(SHADOW_SUN_STEP);
    return fresh ? scroll : shadowGrid.cloudStep.x;
}
// once per frame, after every cloud shadow (with storeShadowGrid)
void storeCloudShadowStep() { shadowGrid.cloudStep = vec2(cloudShadowScroll(), cloudSunStep()); }
#else
float cloudShadowScroll() { return cloudScroll(); }
void storeCloudShadowStep() {}
#endif
float cloudShadow(vec3 worldPos, vec3 lightDir, float filterScale) {
    #ifndef CLOUD_SHADOWS
        return 1.0;
    #else
        #if SHADOW_SUN_STEP > 0 && !defined DIM_END
            lightDir = shadowLightDir();
        #endif
        vec2 gridOffset = vec2(cloudShadowScroll(), cloudZShift());
        if (lightDir.y < 0.02 || !cloudGridKnown()) return 1.0;
        float layer = CLOUD_HEIGHT + CLOUD_THICKNESS * 0.5;
        if (worldPos.y > layer) return 1.0;
        vec2 hit = worldPos.xz + lightDir.xz * ((layer - worldPos.y) / lightDir.y);
        // filterScale 0: one cell, read at the point (TEXEL_SHADOWS: with the receiver at its 1/16 block texel's centre,
        // the cloud shadow has the same hard pixel edge as the other shadows)
        if (filterScale <= 0.0) return cloudCell(ivec2(floor((hit + gridOffset) / CLOUD_CELL))) ? 1.0 - CLOUD_SHADOW_STRENGTH : 1.0;
        float halfWidth = float(clamp(int(CLOUD_SHADOW_FILTER * filterScale + 0.5), 1, 9)) * 0.75 * 0.5 / CLOUD_CELL;   // in cells
        vec2 centre = (hit + gridOffset) / CLOUD_CELL;
        vec2 lo = centre - halfWidth, hi = centre + halfWidth;
        ivec2 first = ivec2(floor(lo));
        float covered = 0.0;
        // the box is at most 9 x 0.75 = 6.75 blocks wide, under one cell: it overlaps 2 x 2 cells at most (a third
        // row or column would have zero area and was skipped anyway)
        for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++) {
            vec2 cell = vec2(first + ivec2(i, j));
            vec2 overlap = max(min(hi, cell + 1.0) - max(lo, cell), 0.0);
            float area = overlap.x * overlap.y;
            if (area > 0.0 && cloudCell(ivec2(cell))) covered += area;
        }
        float s = 1.0 - covered / (4.0 * halfWidth * halfWidth);
        return s < 0.999 ? min(max(s, 1.0 - CLOUD_SHADOW_STRENGTH), 1.0) : 1.0;
    #endif
}
#endif

#endif
