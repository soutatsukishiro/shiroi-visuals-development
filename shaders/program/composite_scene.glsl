// Scene composites, after the translucents.
//  CS_VOLUME  froxel fog and light shafts at the opaque depth (colour x transmittance + in-scattered light), sky
//             objects, late overlays, particles
//  CS_SSR     screen-space reflection of the water surface
//  CS_WATER   water: path extinction, caustics on the floor, surface reflection (key light, sky probe, SSR), the
//             vanilla texture layer, and the fog with the camera in water or lava
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
out vec2 vUv;
void main() { vUv = gl_MultiTexCoord0.xy; gl_Position = sceneClip(ftransform()); }
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/froxel.glsl"
#include "/lib/gbuffer.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler3D volScatterSampler;
uniform sampler2D volColumnSampler;
in vec2 vUv;

// the opaque depth shows the sky: depth 1, or depth with no surface written (colortex3.w == 0, see deferred)
bool opaqueIsSky(float d1, float kind) { return d1 >= 1.0 || kind < 0.25; }

// Opaque depth, counting the forward surfaces drawn after Iris copied depthtex1 (MC 26 draws translucent entity
// parts late: the player, translucent mobs). Those entities leave 2 + view depth in colortex7.a (gbuffers_solid);
// other forward surfaces without a depthtex1 entry (beams, lines, eyes) use depthtex0.
float opaqueDepth(float d0, float d1, float late, float kind) {
    if (late > 1.5) {
        float z = 2.0 - late;   // view-space z (negative)
        float ndc = (gbufferProjection[2][2] * z + gbufferProjection[3][2]) / -z;
        return min(d1, ndc * 0.5 + 0.5);
    }
    if (d1 >= 1.0 && kind > 0.25) return d0;
    return d1;
}

// Volume at the opaque surface; seen through water from above, at the end of its slice segment (lib/froxel.glsl).
// VOL_POPULATE takes the water of a froxel column (8 x 8 pixels at 1080p) from the depths at its centre, and the
// filter blends four columns. Next to the edge of the water that mixed the wrong medium in: ground under ice or beside
// a lake took the water's extinction from a neighbouring column (dark lines along the edge of a frozen river,
// following the bed under the ice, and along shores), and the floor on the shallow side of a step in a lake bed lost
// the water's light. Seen from above (camera out of water), the columns whose water does not match this pixel's
// (volColumn, written by VOL_SCATTER) are left out of the filter; where all four match it is the plain filter.
vec4 volAtOpaque(vec2 uv, float viewDepth, bool throughWater) {
    float z = froxelSlice(viewDepth) * float(FROXEL_GRID.z) - 0.5;
    int k = throughWater ? clamp(int(ceil(z)), 0, FROXEL_GRID.z - 1) : clamp(int(z), 0, FROXEL_GRID.z - 2);
    vec2 p = uv * vec2(FROXEL_GRID.xy) - 0.5;
    ivec2 i0 = ivec2(floor(p));
    ivec2 last = FROXEL_GRID.xy - 1;
    ivec2 c[4] = ivec2[4](clamp(i0, ivec2(0), last), clamp(i0 + ivec2(1, 0), ivec2(0), last),
                          clamp(i0 + ivec2(0, 1), ivec2(0), last), clamp(i0 + ivec2(1, 1), ivec2(0), last));
    bool match[4];
    bool allMatch = true;
    for (int j = 0; j < 4; j++) {
        vec4 water = texelFetch(volColumnSampler, c[j], 0);
        // through water: the column's water reaches this floor's segment; otherwise: no water in slices k, k + 1
        match[j] = throughWater ? water.r > 0.5 && int(ceil(water.g)) >= k : water.r < 0.5 || water.b >= float(k + 1);
        allMatch = allMatch && match[j];
    }
    if (allMatch || isEyeInWater != 0)
        return throughWater ? froxelSegmentEnd(volScatterSampler, uv, viewDepth) : froxelSample(volScatterSampler, uv, viewDepth);
    vec2 f = p - vec2(i0);
    float fz = saturate(z - float(k));
    vec4 sum = vec4(0.0);
    float weight = 0.0;
    for (int j = 0; j < 4; j++) {
        if (!match[j]) continue;
        float w = ((j & 1) != 0 ? f.x : 1.0 - f.x) * ((j >> 1) != 0 ? f.y : 1.0 - f.y);
        vec4 v = texelFetch(volScatterSampler, ivec3(c[j], k), 0);
        if (!throughWater) v = mix(v, texelFetch(volScatterSampler, ivec3(c[j], k + 1), 0), fz);
        sum += w * v;
        weight += w;
    }
    if (weight < 1e-4)
        return throughWater ? froxelSegmentEnd(volScatterSampler, uv, viewDepth) : froxelSample(volScatterSampler, uv, viewDepth);
    return sum / weight;
}

#ifdef CS_VOLUME
#include "/lib/celestial_bloom.glsl"
uniform sampler2D colortex2;
/* RENDERTARGETS: 0,7,4,2 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outDirect;   // colortex7: + the direct light of entities (caustics in CS_WATER)
layout(location = 2) out vec4 outWater;    // colortex4: water surface, removed under particles in front of it
layout(location = 3) out vec4 outGlow;     // preserve RGB; alpha is free after translucents
void main() {
    vec3 col = texture(colortex0, sceneUv(vUv)).rgb;
    vec4 late = texture(colortex7, sceneUv(vUv));      // overlays of late surfaces, a: their depth marker
    vec4 objects = texture(colortex5, sceneUv(vUv));   // sun / moon / stars or an entity's direct light, a: particle coverage
    vec4 water = texture(colortex4, sceneUv(vUv));
    float d0 = texture(depthtex0, sceneUv(vUv)).r;
    float kind = texture(colortex3, sceneUv(vUv)).w;
    float rawD1 = texture(depthtex1, sceneUv(vUv)).r;
    float d1 = opaqueDepth(d0, rawD1, late.a, kind);
    bool sky = opaqueIsSky(d1, kind);
    #ifndef DIM_END
        // the sky objects go on only now: the clouds have covered them, glass and particles have dimmed them
        if (sky) col += objects.rgb;
    #endif
    if (late.a > 1.5) col += late.rgb;   // glint of entities drawn after deferred (deferred adds it for the rest)
    // particles and weather: -(2 + view depth) in colortex7.a, coverage in colortex5.a
    float particleDepth = late.a < -1.5 ? -late.a - 2.0 : -1.0;
    float particleCover = particleDepth > 0.0 ? saturate(objects.a) : 0.0;
    // a particle in front of the water surface (it passed the depth test or wrote its own depth): no water over it
    bool hasWater = water.a > 0.0 && d0 < d1;
    if (hasWater && particleCover > 0.5 && particleDepth <= -screenToView(vUv, d0).z * 1.01) { water = vec4(0.0); hasWater = false; }
    #ifdef VOLUMETRIC_FOG
        float depth = sky ? FROXEL_RANGE.y * 2.0 : -screenToView(vUv, d1).z;
        vec4 vol = volAtOpaque(vUv, depth, hasWater && isEyeInWater == 0);
        if (particleCover > 0.0) vol = mix(vol, froxelSample(volScatterSampler, vUv, particleDepth), particleCover);
        col = sanitize(col * vol.a + vol.rgb);
        #if DEBUG_VIEW == 5
            col = vol.rgb * 10.0;
        #endif
    #endif
    float celestial = sky && !hasWater ? celestialBloomWeight(vUv, objects.rgb, col) : 0.0;
    outColor = vec4(col, 1.0);
    bool forward = kind > 0.25 && kind < 0.75;
    outDirect = vec4(forward ? objects.rgb : late.rgb, late.a);
    outWater = water;
    // r: existing emissive weight; g/b: glass/water coverage. Do not alter them.
    outGlow = vec4(texture(colortex2, sceneUv(vUv)).rgb, celestial);
}
#endif

#ifdef CS_SSR
#include "/lib/ssr.glsl"
/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outSsr;
void main() {
    outSsr = vec4(0.0);
    #ifdef SSR
        vec4 water = texture(colortex4, sceneUv(vUv));
        if (water.a <= 0.0 || isEyeInWater == 1) return;   // most pixels: no water, nothing else to read
        float d0 = texture(depthtex0, sceneUv(vUv)).r;
        float d1 = texture(depthtex1, sceneUv(vUv)).r;
        float lateDepth = texture(colortex7, sceneUv(vUv)).a;
        float kind = texture(colortex3, sceneUv(vUv)).w;
        d1 = opaqueDepth(d0, d1, lateDepth, kind);
        if (d0 >= d1) return;
        vec3 viewPos = rasterToView(vUv, d0);
        vec3 viewNormal = normalize(mat3(gbufferModelView) * octDecode(water.xy * 2.0 - 1.0));
        // traced against the depth that contains the water surface: against the opaque depth the rays hit the
        // river bed (dark bars and cyan sparkles in the reflection)
        vec4 hit = traceScreenReflection(depthtex0, viewPos, viewNormal, unpack2x8(water.z).x, interleavedGradientNoise(gl_FragCoord.xy));
        if (hit.w > 0.0 && texture(colortex4, sceneUv(hit.xy)).a <= 0.0) outSsr = vec4(sanitize(texture(colortex0, sceneUv(hit.xy)).rgb), hit.w);
    #endif
}
#endif

#ifdef CS_WATER
#include "/lib/shading.glsl"
/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

uniform sampler2D colortex1;     // water texture layer (gbuffers_water): vanilla texture x biome colour, alpha
uniform sampler2D colortex2;     // b: what the translucents in front of the water let through, g: coverage of all
                                 // translucents but water (gbuffers_translucent)
uniform float waterEyeAdapt;     // shaders.properties: 0 when the camera enters the water -> 1 after ~30 s

// Fresnel reflectance of water: Schlick with F0 = ((n - 1) / (n + 1))^2 = 0.02 for n = 1.33
float waterFresnel(float cosTheta) { return pow5(saturate(1.0 - cosTheta)) * 0.98 + 0.02; }

// share of the light the surface reflects. From below the transmitted ray goes into air: Snell gives
// sin^2(t) = n^2 sin^2(i) with n^2 = 1.7689, and past the critical angle (sin^2(i) > 1 / n^2) all is reflected
float surfaceReflectance(float cosView) {
    if (isEyeInWater != 1) return waterFresnel(cosView);
    float sin2 = 1.0 - cosView * cosView;
    return sin2 > 0.565323055 ? 1.0 : waterFresnel(sqrt(1.0 - sin2 * 1.76890016));
}

// colour of a fog the camera is inside (water, powder snow): the medium's tint lit by the sky ambient at the camera
// plus twice the block light, never below 1. The sky ambient is the one a surface at the camera would get (sky
// probe x the ambient share x the sky light response): with the whole sky irradiance the water fog was about twice
// as bright as the lit floor at noon, a pale wall. It follows the daylight (with the floor of 1 alone the water was
// a bright wall at night).
vec3 mediumFogColour(vec3 tint, Daylight L) {
    float day = clamp(sin(sunAngle * 6.2831853) * 2.0 + 0.5, 0.0, 1.0);
    vec3 skyAtEye = skyIrradianceNow() * skyLightResponse(L.eyeSky);
    return max(skyAtEye + L.blockScale * 2.0, vec3(1.0)) * tint * mix(0.2, 1.0, day);
}
vec3 underwaterFogColour(Daylight L) {
    return mediumFogColour(srgbToLinear(mix(UNDERWATER_FOG, PALE_UNDERWATER_FOG, saturate(paleGardenWeight)) / 255.0), L);
}
// the fog closes in at a quarter of its distance right after diving and opens up while the eye adapts
float underwaterFogEnd() { return UNDERWATER_FOG_END * mix(UNDERWATER_FOG_FIRST, 1.0, saturate(waterEyeAdapt)); }

// key light visibility at the surface point: shadow map (offset straight up), cloud shadow, range fade
float waterKeyVisibility(vec3 pos, float viewDepth, Daylight L) {
    ShadowSample sm = shadowLookup(pos, vec3(0.0, 1.0, 0.0), 1.0, false);
    float vis = sm.cascade < 0 ? 1.0 : sm.visibility;
    #ifdef TEXEL_SHADOWS
        vis = min(vis, cloudShadow(snapToTexelCentre(pos, vec3(0.0, 1.0, 0.0)) + cameraPosition, L.keyDir, 0.0));
    #else
        vis = min(vis, cloudShadow(pos + cameraPosition, L.keyDir, 1.0));
    #endif
    return shadowRangeFade(vis, viewDepth);
}

// GGX highlight of the key light (the terms of lib/shading.glsl keyLight, with the water Fresnel)
vec3 waterKeySpecular(vec3 N, vec3 V, float roughness, float visibility, Daylight L) {
    vec3 H = normalize(L.keyDir - V);
    float NdotL = max(dot(N, L.keyDir), 0.0), NdotV = max(dot(N, -V), 0.0);
    float alpha = max(roughness, 0.05); alpha *= alpha;
    float k = alpha * 0.5;
    float D = ggxDistribution(max(dot(N, H), 0.0), alpha * alpha);
    float G = smithSchlickG1(NdotV, k) * smithSchlickG1(NdotL, k);
    float F = waterFresnel(max(dot(-V, H), 0.0));
    return vec3(D * F * G / (NdotL * NdotV * 4.0 + 0.0001) * NdotL) * visibility * L.keyLight;
}

// reflected environment: sky probe, the screen-space reflection over it where it hit, split-sum BRDF with F0 0.02
vec3 waterEnvironment(vec3 V, vec3 N, float roughness, float probeFade, Daylight L) {
    vec3 env = vec3(0.0);
    #ifdef IBL
        env = probeSample(colortex14, reflect(V, N), probeLevel(roughness)) * probeFade * PROBE_REFLECTION_GAIN;
    #endif
    // from below the reflection points back into the water, which the sky probe does not hold (it showed grey ground
    // colours in the total internal reflection): reflect the underwater fog instead
    if (isEyeInWater == 1) env = underwaterFogColour(L);
    vec4 ssr = texture(colortex5, sceneUv(vUv));
    env = mix(env, ssr.rgb, saturate(ssr.a));
    vec2 split = texture(brdfLut, vec2(saturate(dot(N, -V)), 1.0 - roughness)).rg;
    return env * (0.02 * split.x + split.y);
}

// Caustics on the floor under the surface: the change they make to the floor's direct light (colortex7). The floor
// colour has already been through the volume (col x T + S), so the change is scaled by the same T; otherwise the
// darker parts of the pattern ate through the attenuated floor (black / magenta) and never faded with depth.
// floorShare: what the translucents between the surface and the floor let through (the floor's part of col)
vec3 withFloorCaustics(vec3 col, vec3 floorView, float floorShare) {
    vec3 floorPos = viewToPlayer(floorView) + cameraPosition;
    vec3 direct = texture(colortex7, sceneUv(vUv)).rgb;
    float floorT = floorShare;
    #ifdef VOLUMETRIC_FOG
        floorT *= volAtOpaque(vUv, -floorView.z, true).a;
    #endif
    return max(col + direct * floorT * (causticFactor(floorPos, vec3(0.0, 1.0, 0.0)) - 1.0), 0.0);
}

void main() {
    // most pixels: no water surface and the camera in air, the colour passes through unchanged
    if (isEyeInWater == 0 && texture(colortex4, sceneUv(vUv)).a <= 0.0) {
        outColor = vec4(sanitize(texture(colortex0, sceneUv(vUv)).rgb), 1.0);
        return;
    }
    Daylight L = daylight();
    vec3 col = texture(colortex0, sceneUv(vUv)).rgb;
    float d0 = texture(depthtex0, sceneUv(vUv)).r;
    float lateDepth = texture(colortex7, sceneUv(vUv)).a;
    float kind = texture(colortex3, sceneUv(vUv)).w;
    float d1 = opaqueDepth(d0, texture(depthtex1, sceneUv(vUv)).r, lateDepth, kind);
    vec4 water = texture(colortex4, sceneUv(vUv));
    bool hasWater = water.a > 0.0 && d0 < d1;
    vec3 surfaceView = rasterToView(vUv, d0);
    vec3 floorView = rasterToView(vUv, d1);
    bool skyBehind = opaqueIsSky(d1, kind);
    float surfaceDist = length(surfaceView), floorDist = skyBehind ? far : length(floorView);
    vec3 extinction = waterExtinction();
    // translucent blocks in front of the water surface (ice over a frozen lake, stained glass): what they let through
    // (colortex2.b) and, without WATER_TEXTURE, the colour they added (colortex1), both from gbuffers_translucent. The
    // water goes under them: the scene behind them is taken out, the water applied to it, and they are put back on
    // top. Before, ice erased the water under it and the lake floor showed as if dry.
    // Translucents drawn before the water lie under its surface (the submerged part of the ice faces at a hole or at the
    // edge of the ice): taken as lake floor they got the extinction of the whole depth and the floor's caustics taken
    // off their dim colour, black strips along the ice. 'behind' is what they let through: the floor's share of col.
    vec3 beforeWater = col, frontColour = vec3(0.0);
    float front = 1.0, behind = 1.0;
    if (hasWater) {
        vec4 cover = texture(colortex2, sceneUv(vUv));
        front = cover.b;
        if (front > 0.02) behind = saturate((1.0 - cover.g) / front);
        #ifndef WATER_TEXTURE
            frontColour = texture(colortex1, sceneUv(vUv)).rgb;
            if (front > 0.02) col = max(col - frontColour, 0.0) / front;
        #endif
    }

    if (hasWater) {
        vec3 pos = viewToPlayer(surfaceView);
        vec3 V = normalize(pos);
        vec3 N = octDecode(water.xy * 2.0 - 1.0);
        vec2 roughSky = unpack2x8(water.z);   // roughness | sky light of the water surface
        float roughness = roughSky.x;
        float skyLevel = roughSky.y;
        float viewDepth = -surfaceView.z;

        #ifdef WATER_CAUSTICS
            if (isEyeInWater == 0 && !skyBehind) col = withFloorCaustics(col, floorView, behind);
        #endif
        // seen from above: Beer-Lambert over the water between the surface and the floor; the translucents under the
        // surface (their depth is not kept) get at most a block of it
        if (isEyeInWater == 0) {
            float path = min(floorDist, far) - min(surfaceDist, far);
            col *= mix(exp(-min(path, 1.0) * extinction), exp(-path * extinction), behind);
        }

        // the key light needs sky light, a light that is on, and to be above the horizon
        bool keyLit = skyLevel >= 0.5 / 255.0 && dot(L.keyLight, vec3(1.0)) > 0.0 && L.keyDir.y > 0.0;
        float keyVis = keyLit ? waterKeyVisibility(pos, viewDepth, L) : 0.0;
        vec3 spec = keyLit && dot(N, L.keyDir) > 0.0 ? waterKeySpecular(N, V, roughness, keyVis, L) : vec3(0.0);
        // where the sky probe fades out (little sky light) the surface reflects the ambient light instead
        float probeFade = probeSkyFade(skyLevel);
        vec3 ambient = max(skyLightResponse(skyLevel) * skyIrradianceNow(), L.ambientFloor);
        spec += (1.0 - probeFade) * waterFresnel(max(dot(-V, N), 0.0)) * ambient;
        vec3 indirect = waterEnvironment(V, N, roughness, probeFade, L);

        float fogT = fogAmount(surfaceDist, L);
        vec3 fogCol = fogTint(V, skyLevel, L);
        vec3 surface = mix(spec, fogCol, fogT) + indirect * (1.0 - fogT);
        #ifdef VOLUMETRIC_FOG
            vec4 vol = froxelSample(volScatterSampler, vUv, viewDepth);
            surface = surface * vol.a + vol.rgb;
        #endif

        // the vanilla water texture (biome tinted) as a thin diffuse layer on the surface, lit by the ambient and the
        // key light, over what is seen through it
        #ifdef WATER_TEXTURE
            vec4 layer = texture(colortex1, sceneUv(vUv));
            float coverage = saturate(layer.a * WATER_TEXTURE_OPACITY);
            if (coverage > 0.0) {
                vec3 lit = srgbToLinear(layer.rgb) * (ambient + L.keyLight * max(dot(N, L.keyDir), 0.0) * keyVis * INV_PI);
                lit = mix(lit, fogCol, fogT);
                #ifdef VOLUMETRIC_FOG
                    lit = lit * vol.a + vol.rgb;
                #endif
                col = mix(col, lit, coverage);
            }
        #endif
        col = surface + col * (1.0 - surfaceReflectance(max(dot(-V, N), 0.0)));
        // the translucents in front back on top (with the water texture layer in colortex1 their colour is unknown:
        // the water result is then blended in by their transmittance)
        #ifdef WATER_TEXTURE
            col = mix(beforeWater, col, front);
        #else
            col = front > 0.02 ? frontColour + front * col : beforeWater;
        #endif
    }

    if (isEyeInWater == 1) {
        // camera in water: extinction along the view path and the distance fog
        float path = hasWater ? surfaceDist : floorDist;
        col *= exp(-path * extinction);
        col = mix(col, underwaterFogColour(L), saturate(path / underwaterFogEnd()));
    } else if (isEyeInWater == 2) {
        // camera in lava: complete at two thirds of LAVA_FOG_END
        col = mix(col, srgbToLinear(LAVA_FOG / 255.0) * LAVA_FOG_GAIN, saturate(floorDist / LAVA_FOG_END * 1.5));
    } else if (isEyeInWater == 3) {
        // camera in powder snow: the faces of the block around the camera are not drawn, so without this fog the
        // snow vanished around it; complete at POWDER_SNOW_FOG_END, nearly all white
        float path = hasWater ? surfaceDist : floorDist;
        col = mix(col, mediumFogColour(srgbToLinear(POWDER_SNOW_FOG / 255.0), L), saturate(path / POWDER_SNOW_FOG_END));
    }
    outColor = vec4(sanitize(col), 1.0);
}
#endif
#endif
