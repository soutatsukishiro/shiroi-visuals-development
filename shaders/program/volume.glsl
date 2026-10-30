// Froxel volume, three compute passes (see lib/froxel.glsl):
//  VOL_SHADOW   light visibility of every froxel: shadow map x cloud shadow at a jittered point inside it,
//               accumulated over frames by reprojecting into the previous frame's grid (ping-pong A / B)
//  VOL_POPULATE medium of every froxel (air, pale garden fog or water) and the light it scatters: sky ambient
//               (isotropic) + key light through a Henyey-Greenstein phase function
//  VOL_SCATTER  front-to-back integration along each froxel column (Beer-Lambert per segment)
#include "/lib/common.glsl"
#include "/lib/froxel.glsl"

// Iris parses workGroups with Integer.parseInt per component: only integer literals are accepted (an expression
// silently falls back to one group per 8x8 screen pixels with z = 1)
#ifdef VOL_SCATTER
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;   // one thread per column
#else
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
#endif
#if VOLUME_QUALITY == 3
    #ifdef VOL_SCATTER
        const ivec3 workGroups = ivec3(30, 17, 1);
    #else
        const ivec3 workGroups = ivec3(30, 17, 12);
    #endif
#elif VOLUME_QUALITY == 2
    #ifdef VOL_SCATTER
        const ivec3 workGroups = ivec3(30, 17, 1);
    #else
        const ivec3 workGroups = ivec3(30, 17, 6);
    #endif
#elif VOLUME_QUALITY == 1
    #ifdef VOL_SCATTER
        const ivec3 workGroups = ivec3(15, 9, 1);
    #else
        const ivec3 workGroups = ivec3(15, 9, 8);
    #endif
#else
    #ifdef VOL_SCATTER
        const ivec3 workGroups = ivec3(4, 3, 1);
    #else
        const ivec3 workGroups = ivec3(4, 3, 4);
    #endif
#endif

// player-space position of a point given in froxel units
vec3 froxelPlayerPos(vec3 f) {
    vec3 t = f / vec3(FROXEL_GRID);
    return viewToPlayer(froxelViewPos(t.xy, froxelDepth(t.z)));
}

#ifdef VOL_SHADOW
#include "/lib/shadowmap.glsl"
writeonly uniform image3D volShadowA;
writeonly uniform image3D volShadowB;
uniform sampler3D volShadowASampler;
uniform sampler3D volShadowBSampler;

const float HISTORY_WEIGHT = 0.9;     // share of the previous frames kept
const float HISTORY_REJECT = 1.0;     // how fast the history is dropped once the point leaves the old grid (froxels)

void main() {
    ivec3 id = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(id, FROXEL_GRID))) return;
    vec3 toLight = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    // a different point inside the froxel every frame: R3 low-discrepancy sequence [Roberts 2018]
    #ifdef VOLUME_TEMPORAL
        vec3 jitter = fract(vec3(0.5) + float(frameCounter % 64) * vec3(0.8191725134, 0.6710436067, 0.5497004779)) - 0.5;
    #else
        vec3 jitter = vec3(0.0);
    #endif
    // past the shadow range the fade makes the visibility exactly 1 whatever the lookups return: skip them there
    float centreDepth = froxelDepth((float(id.z) + 0.5) / float(FROXEL_GRID.z));
    float visible = 1.0;
    if (centreDepth < SHADOW_RANGE) {
        vec3 p = froxelPlayerPos(vec3(id) + 0.5 + jitter);
        #ifdef VOLUME_FAST_SHADOWS
            ShadowSample sm = shadowLookup(p, vec3(0.0), 0.125, false);
        #else
            ShadowSample sm = shadowLookup(p, vec3(0.0), FROXEL_SHADOW_FILTER, false);
        #endif
        visible = sm.cascade < 0 ? 1.0 : sm.visibility;
        visible = min(visible, cloudShadow(p + cameraPosition, toLight, FROXEL_SHADOW_FILTER));
    }
    visible = shadowRangeFade(visible, centreDepth);

    bool evenFrame = (frameCounter & 1) == 0;
    #ifdef VOLUME_TEMPORAL
        // where the froxel centre was in the previous frame's grid
        vec3 prevPlayer = froxelPlayerPos(vec3(id) + 0.5) + cameraPosition - previousCameraPosition;
        vec4 prevView = gbufferPreviousModelView * vec4(prevPlayer, 1.0);
        vec4 prevClip = gbufferPreviousProjection * prevView;
        vec2 prevUv = (prevClip.xy / prevClip.w) * 0.5 + 0.5;
        float prevDepth = -prevView.z;
        vec3 g = vec3(prevUv * vec2(FROXEL_GRID.xy), froxelSlice(prevDepth) * float(FROXEL_GRID.z));
        float outside = saturate(length(clamp(g, vec3(0.0), vec3(FROXEL_GRID)) - g) * HISTORY_REJECT);
        float history = evenFrame ? froxelSample(volShadowBSampler, prevUv, prevDepth).r : froxelSample(volShadowASampler, prevUv, prevDepth).r;
        if (frameCounter > 2) visible = mix(visible, history, HISTORY_WEIGHT * (1.0 - outside));
    #endif
    if (evenFrame) imageStore(volShadowA, id, vec4(visible));
    else imageStore(volShadowB, id, vec4(visible));
}
#endif

#ifdef VOL_POPULATE
#include "/lib/skymodel.glsl"
#if defined COLORED_LIGHT && defined VOL_BLOCK_LIGHT
    #define LC_SAMPLE
    #include "/lib/lightcolor.glsl"
#endif
#define PROBE_SAMPLER
#include "/lib/skyprobe.glsl"
writeonly uniform image3D volMedia;
uniform sampler3D volShadowASampler;
uniform sampler3D volShadowBSampler;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex14;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;

float viewDepthAt(vec2 uv, float d) { return -screenToView(uv, d).z; }

// Henyey-Greenstein phase function for the angle between the view ray and the direction to the light
float henyeyGreenstein(float g, float cosTheta) {
    float den = g * g + 1.0 - 2.0 * g * cosTheta;
    return (1.0 - g * g) * INV_4PI / (sqrt(den) * den);
}

void main() {
    ivec3 id = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(id, FROXEL_GRID))) return;
    Daylight L = daylight();
    Media m = participatingMedia();
    vec3 t = (vec3(id) + 0.5) / vec3(FROXEL_GRID);
    float depth = froxelDepth(t.z);
    vec3 viewPos = froxelViewPos(t.xy, depth);
    vec3 worldPos = viewToPlayer(viewPos) + cameraPosition;

    // share of this froxel's segment (previous centre, this centre] that lies in water: between the water surface
    // (depth with translucents) and the opaque surface behind it
    float water = 0.0;
    if (texture(colortex4, sceneUv(t.xy)).a > 0.0) {
        float surface = viewDepthAt(t.xy, texture(depthtex0, sceneUv(t.xy)).r);
        float floorDepth = viewDepthAt(t.xy, texture(depthtex1, sceneUv(t.xy)).r);
        float segStart = froxelDepth((float(id.z) - 0.5) / float(FROXEL_GRID.z));
        water = saturate((min(depth, floorDepth) - max(segStart, surface)) / max(depth - segStart, 1e-4));
    }
    if (isEyeInWater == 1) water = 1.0 - water;

    // the air is dense below m.airTop and empty above it
    float airShare = saturate(-1000.0 * worldPos.y + (m.airTop * 1000.0 + 1.0));
    vec3 scattering = mix((airShare * m.airAlbedo) * m.airExtinction, m.waterAlbedo * m.waterExtinction, water);
    float extinction = mix(airShare * m.airExtinction, m.waterExtinction, water);
    // the distance fog takes over at the end of the render distance
    float keep = 1.0 - fogAmount(length(viewPos), L);
    scattering *= keep;
    extinction *= keep;

    // how much of the sky this point of the fog sees. The target look reads it from a volume of sky visibility
    // (T_SkyAmbientSamples) at every point; here it runs along the view ray from the sky light at the camera to the
    // sky light of the surface behind (open sky where there is none): the fog under trees, in a cave mouth or by a
    // wall gets the sky light there, not the camera's. Under water as before (the water's light is matched to it)
    float skyVis = L.eyeSky;
    #ifdef VOL_SKY_VISIBILITY
        float opaque = texture(depthtex1, sceneUv(t.xy)).r;
        vec4 behind = texture(colortex3, sceneUv(t.xy));
        float behindSky = opaque >= 1.0 || behind.w < 0.25 ? 1.0 : behind.y;
        float along = saturate(depth / max(viewDepthAt(t.xy, opaque), 1e-3));
        skyVis = mix(mix(L.eyeSky, behindSky, along), L.eyeSky, water);
    #endif
    // sky ambient, isotropic, scaled by the sky visibility there
    vec3 skyIrradiance = probeIrradiance(colortex14) * SKY_IRRADIANCE_GAIN * SKY_INTENSITY;
    vec3 inscatter = scattering * max(skyVis * skyIrradiance, vec3(m.ambientFloor)) * INV_4PI;
    #if defined COLORED_LIGHT && defined VOL_BLOCK_LIGHT
        // block light in the fog, as the target look's volume adds the block ambient of the voxels around (block base
        // ambient x the voxel's light x 6, the same ambient its surfaces get): torches and lamps light the fog around
        // them, in their colour. The light level there is not known in this pass: it comes from the light colour grid
        // (lib/lightcolor.glsl), whose weight spreads around each light with a Gaussian of ~5 blocks: the distance to
        // the light from the weight, then one level less per block, as the game's block light (a glowstone gives the
        // grid ~0.027 at the 0.7-0.9 light level around it)
        vec3 lcp = worldPos / LC_CELL - vec3(lcOrigin(cameraPosition));
        vec3 lcEdge = min(lcp, vec3(LC_GRID) - lcp);
        if (all(greaterThan(lcEdge, vec3(0.5)))) {
            vec4 lc = (frameCounter & 1) == 0 ? texture(lcCSampler, lcp / vec3(LC_GRID)) : texture(lcDSampler, lcp / vec3(LC_GRID));
            if (lc.a > 1e-4) {
                float lightDist = sqrt(max(-50.0 * log(min(lc.a / VOL_BLOCK_LIGHT_PEAK, 1.0)), 0.0));
                float level = saturate(1.0 - lightDist / 15.0) * saturate(min(lcEdge.x, min(lcEdge.y, lcEdge.z)) / 4.0);
                vec3 blockAmbient = blockLightColor(level) * L.blockScale;
                vec3 hue = lc.rgb / lc.a; hue /= max(hue.r, max(hue.g, hue.b));
                float colourful = smoothstep(0.25, 0.4, distance(hue, LC_TORCH_HUE));
                vec3 c = pow(hue, vec3(COLORED_LIGHT_SATURATION));
                blockAmbient = mix(blockAmbient, c * (max(blockAmbient.r, max(blockAmbient.g, blockAmbient.b)) / max(c.r, max(c.g, c.b))), colourful);
                inscatter += scattering * blockAmbient * INV_4PI;
            }
        }
    #endif
    // key light, only where this point sees the sky (the target look's sky light heuristic; the shadow volume does
    // the rest)
    if (skyVis > 0.0001) {
        vec3 toLightView = normalize(mat3(gbufferModelView) * L.keyDir);
        float phase = henyeyGreenstein(mix(m.airG, m.waterG, water), dot(normalize(viewPos), toLightView));
        float visible = (frameCounter & 1) == 0 ? texelFetch(volShadowASampler, id, 0).r : texelFetch(volShadowBSampler, id, 0).r;
        inscatter += visible * scattering * phase * L.keyLight;
    }
    imageStore(volMedia, id, vec4(inscatter, extinction));
}
#endif

#ifdef VOL_SCATTER
uniform sampler3D volMediaSampler;
writeonly uniform image3D volScatter;
writeonly uniform image2D volColumn;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
void main() {
    ivec2 column = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(column, FROXEL_GRID.xy))) return;
    // the water VOL_POPULATE gave this column, from the depths at its centre (program/composite_scene.glsl volAtOpaque):
    // r 1 with water, g / b slice coordinate of the floor / the water surface
    vec2 centre = (vec2(column) + 0.5) / vec2(FROXEL_GRID.xy);
    vec4 water = vec4(0.0);
    if (texture(colortex4, sceneUv(centre)).a > 0.0) {
        water.r = 1.0;
        water.g = froxelSlice(-screenToView(centre, texture(depthtex1, sceneUv(centre)).r).z) * float(FROXEL_GRID.z) - 0.5;
        water.b = froxelSlice(-screenToView(centre, texture(depthtex0, sceneUv(centre)).r).z) * float(FROXEL_GRID.z) - 0.5;
    }
    imageStore(volColumn, column, water);
    // result per slice: rgb = light scattered towards the camera so far, a = transmittance so far
    vec4 acc = vec4(0.0, 0.0, 0.0, 1.0);
    float segStart = froxelDepth(-0.5 / float(FROXEL_GRID.z));
    for (int k = 0; k < FROXEL_GRID.z; k++) {
        float segEnd = froxelDepth((float(k) + 0.5) / float(FROXEL_GRID.z));
        float len = segEnd - segStart;
        vec4 medium = texelFetch(volMediaSampler, ivec3(column, k), 0);
        float T = exp(-len * medium.w);
        // in-scatter integrated over the segment: S (1 - e^(-sigma len)) / sigma
        float integral = abs(medium.w) > 1e-6 ? (1.0 - T) / medium.w : len;
        acc.rgb += acc.a * integral * medium.rgb;
        acc.a *= T;
        imageStore(volScatter, ivec3(column, k), acc);
        segStart = segEnd;
    }
}
#endif
