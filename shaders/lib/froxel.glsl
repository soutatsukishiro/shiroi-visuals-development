#ifndef FROXEL_GLSL
#define FROXEL_GLSL
// Frustum-aligned voxel ("froxel") volume for fog and light shafts [Wronski 2014; Hillaire 2015].
//  * x, y follow the screen; slice t in 0..1 maps to view depth exponentially:
//    depth = near + (far - near) (e^(4t) - 1) / (e^4 - 1), dense near the camera
//  * every froxel stores in-scattered light and extinction; a front-to-back pass turns them into the light
//    scattered towards the camera and the transmittance from the camera up to each slice (Beer-Lambert)
//  * a surface at view depth d is then fogged as colour * T(d) + S(d)
#include "/lib/common.glsl"
#include "/lib/look.glsl"

const float E4_MINUS_1 = 53.59815;     // e^4 - 1
const float LOG2_E4 = 5.77078;         // log2(e^4) = 4 / ln 2

float froxelDepth(float t) {
    float s = (exp2(t * LOG2_E4) - 1.0) / E4_MINUS_1;
    return mix(FROXEL_RANGE.x, FROXEL_RANGE.y, s);
}
float froxelSlice(float depth) {
    float x = (depth - FROXEL_RANGE.x) / (FROXEL_RANGE.y - FROXEL_RANGE.x);
    return log2(max(x * E4_MINUS_1 + 1.0, 1e-6)) / LOG2_E4;
}
// view-space position of screen uv at a view depth
vec3 froxelViewPos(vec2 uv, float depth) {
    vec3 p = screenToView(uv, 0.5);
    return p * (depth / max(-p.z, 1e-6));
}

// bilinear filter in x, y of one slice (done by hand: image samplers are not guaranteed to be filtered)
vec4 froxelSliceBilinear(sampler3D vol, vec2 uv, int slice) {
    vec2 p = uv * vec2(FROXEL_GRID.xy) - 0.5;
    ivec2 i0 = ivec2(floor(p));
    vec2 f = p - vec2(i0);
    ivec2 last = FROXEL_GRID.xy - 1;
    vec4 a = texelFetch(vol, ivec3(clamp(i0, ivec2(0), last), slice), 0);
    vec4 b = texelFetch(vol, ivec3(clamp(i0 + ivec2(1, 0), ivec2(0), last), slice), 0);
    vec4 c = texelFetch(vol, ivec3(clamp(i0 + ivec2(0, 1), ivec2(0), last), slice), 0);
    vec4 d = texelFetch(vol, ivec3(clamp(i0 + ivec2(1, 1), ivec2(0), last), slice), 0);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
// trilinear value at a view depth (slice centres sit at (k + 0.5) / slices)
vec4 froxelSample(sampler3D vol, vec2 uv, float depth) {
    float z = froxelSlice(depth) * float(FROXEL_GRID.z) - 0.5;
    int k = clamp(int(z), 0, FROXEL_GRID.z - 2);
    return mix(froxelSliceBilinear(vol, uv, k), froxelSliceBilinear(vol, uv, k + 1), saturate(z - float(k)));
}
// value at the far end of the slice segment that contains the depth. Slice k integrates (centre k-1, centre k],
// and the media pass gives each segment the fraction of it that lies in water, so where a surface ends the water
// (the lake floor seen from above) the segment end holds the exact water path; interpolating between centres
// would lose the water between the last centre and the floor (visible as stripes, one per slice).
vec4 froxelSegmentEnd(sampler3D vol, vec2 uv, float depth) {
    float z = froxelSlice(depth) * float(FROXEL_GRID.z) - 0.5;
    return froxelSliceBilinear(vol, uv, clamp(int(ceil(z)), 0, FROXEL_GRID.z - 1));
}

// ------------------------------------------------------------------ media
struct Media {
    vec3 airAlbedo; float airExtinction;   // albedo per channel, mean extinction
    float airTop;                          // the air is dense up to this height
    vec3 waterAlbedo; float waterExtinction;
    float airG, waterG;                    // Henyey-Greenstein anisotropy
    float ambientFloor;
};

Media participatingMedia() {
    Media m;
    float pale = 0.0;
    // the air of the biome (shaders.properties, from the fog settings); defaults when not available
    float airDensity = AIR_DENSITY, airG = AIR_G;
    vec3 airScattering = AIR_SCATTERING, airAbsorption = AIR_ABSORPTION;
    #if !defined DIM_NETHER && !defined DIM_END
        // the pale garden and the sulfur caves share the dense air
        pale = max(saturate(paleGardenWeight), saturate(sulfurCavesWeight));
        if (biomeLookReady > 0.5) {
            airDensity = biomeFogDensity;
            airScattering = vec3(biomeFogScatter);
            airAbsorption = vec3(biomeFogAbsR, biomeFogAbsG, biomeFogAbsB);
            airG = biomeFogG;
        }
    #endif
    float density = mix(airDensity, PALE_DENSITY, pale) * FOG_DENSITY_MUL;
    vec3 scattering = mix(airScattering, PALE_SCATTERING, pale), absorption = mix(airAbsorption, PALE_ABSORPTION, pale);
    vec3 extinction = max(scattering + absorption, vec3(1e-6));
    m.airAlbedo = scattering / extinction;
    m.airExtinction = dot(extinction, vec3(1.0 / 3.0)) * density;
    m.airTop = AIR_TOP;
#ifdef MOD_COMPAT
    m.airTop = mcCompatWorldTop(m.airTop);
#endif

    m.waterExtinction = 0.1784;   // mean of WATER_EXTINCTION
    m.waterAlbedo = WATER_SCATTERING / m.waterExtinction;
    m.airG = mix(airG, PALE_G, pale);
    m.waterG = WATER_G;
    m.ambientFloor = 0.0;
    #if defined DIM_NETHER
        m.airAlbedo = vec3(1.0); m.airExtinction = 0.0;        // the Nether has no volumetric fog
    #elif defined DIM_END
        m.airAlbedo = vec3(1.0); m.airExtinction = END_FOG_SCATTERING * (END_FOG_DENSITY * FOG_DENSITY_MUL);
        m.airG = END_FOG_G; m.waterG = END_FOG_G;
    #endif

#ifdef MOD_COMPAT
    if (mcCompatSkyless()) m.airExtinction = 0.0;
#endif
    return m;
}

// extinction of clear water per channel (used for the view path through water)
vec3 waterExtinction() { return WATER_EXTINCTION; }

#endif
