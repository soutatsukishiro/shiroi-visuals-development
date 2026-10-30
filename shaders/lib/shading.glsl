#ifndef SHADING_GLSL
#define SHADING_GLSL
// Surface lighting, shared by the deferred pass and the forward-shaded geometry.
//  key light   the shadow-casting sun or moon. Lambert diffuse, with wrap lighting and a back-lit transmission lobe
//              for subsurface materials; Cook-Torrance specular with the GGX normal distribution [Walter et al.
//              2007], the Schlick-Smith visibility with k = alpha / 2 [Schlick 1994; Karis 2013] and Schlick's
//              Fresnel approximation. Visibility = cascaded shadow map x cloud shadow.
//  ambient     warm block light + sky light (lightmap response x sky probe irradiance), never below a floor.
//  reflections pre-filtered sky probe + split-sum BRDF table [Karis 2013], screen-space reflection over it.
//  fog         the surface fades into the sky colour over the last part of the render distance.
#include "/lib/skymodel.glsl"
#include "/lib/shadowmap.glsl"
#define PROBE_SAMPLER
#include "/lib/skyprobe.glsl"

uniform sampler2D colortex14;   // sky probe (prepare passes)
uniform sampler2D brdfLut;      // split-sum table: x = N.V, y = 1 - roughness
uniform sampler2D causticsTex;  // caustic animation, CAUSTIC_FRAMES frames stacked vertically

struct Surface {
    vec3 albedo;      // linear
    float metal;
    float sss;        // subsurface amount
    float roughness;  // perceptual
    float emissive;
    float blockLevel; // lightmap, 0..1
    float skyLevel;   // lightmap, 0..1
    vec3 normal;      // shading normal (player space, may carry micro detail)
    vec3 flatNormal;  // geometric normal (shadow lookups)
    vec3 pos;         // player space
    float viewDepth;  // distance along the view axis
};

struct KeyLightResult { vec3 diffuse; vec3 specular; float shadow; };

// ------------------------------------------------------------------ light sources

// response to the sky lightmap: s^5, blended towards s^3 by SKY_LIGHT_CURVE
float skyLightResponse(float s) {
    float s2 = s * s;
    float s3 = s2 * s, s5 = s2 * s2 * s;
    return SKY_LIGHT_CURVE * (s3 - s5) + s5;
}

// irradiance of the whole sky, from the probe's integrated texel
vec3 skyIrradianceNow() { return probeIrradiance(colortex14) * SKY_IRRADIANCE_GAIN * SKY_INTENSITY; }

#if defined COLORED_LIGHT || defined HAND_LIGHT
    #define LC_SAMPLE
    #include "/lib/lightcolor.glsl"
#endif
// block light at the surface: the lightmap, raised by a held light, in the colour of the lights around (worked out
// once per shader invocation: the ambient and the specular terms both ask for it)
#if defined COLORED_LIGHT || defined HAND_LIGHT
    vec3 cachedBlockLight;
    bool blockLightCached = false;
#endif
vec3 surfaceBlockLight(Surface s) {
    #if defined COLORED_LIGHT || defined HAND_LIGHT
        if (blockLightCached) return cachedBlockLight;
        blockLightCached = true;
        vec3 handHue;
        float hand = handLight(s.pos, handHue);
        vec3 base = blockLightColor(max(s.blockLevel, hand));
        cachedBlockLight = base;
        if (max(s.blockLevel, hand) <= 0.0) return base;   // no block light here: nothing to colour (most of a day scene)
        vec4 hue = blockLightHue(s.pos, hand, handHue, s.blockLevel);
        if (hue.a > 0.0) {
            // the hue changes, the strongest channel stays: a red light is as bright as a white one in red, not
            // brighter (keeping the luminance needed ~4.7 x more red: snow around a redstone torch went bright pink)
            vec3 c = pow(hue.rgb, vec3(COLORED_LIGHT_SATURATION));
            base = mix(base, c * (max(base.r, max(base.g, base.b)) / max(c.r, max(c.g, c.b))), hue.a);
        }
        cachedBlockLight = base;
        return base;
    #else
        return blockLightColor(s.blockLevel);
    #endif
}

// depth under the water surface (blocks) of a point under water: the game's sky light loses a level per block of
// water, so down to 15 blocks it gives the depth; deeper it reads 0, and the sea level stands in for the surface
float waterDepthAt(float skyLevel, float worldY) {
    return skyLevel > 0.0 ? (1.0 - skyLevel) * 15.0 : max(15.0, UNDERWATER_SEA_LEVEL - worldY);
}
// the sky's share at a surface. With the camera under water the sky reaches what it sees through the water above:
// by the lightmap alone a sea floor deeper than 15 blocks got none (lit by the sun's caustics only, a harsh net on
// black) where the target look lights it softly
float skyAmbientShare(Surface s) {
    float share = skyLightResponse(s.skyLevel) * skyAmbientBoost();
    if (isEyeInWater == 1)
        share = max(share, exp(-waterDepthAt(s.skyLevel, s.pos.y + cameraPosition.y) * UNDERWATER_LIGHT_FALLOFF) * UNDERWATER_AMBIENT);
    return share;
}
vec3 ambientLight(Surface s, Daylight L, vec3 skyIrradiance) {
    vec3 floorLight = L.ambientFloor * (isEyeInWater == 1 ? UNDERWATER_AMBIENT_FLOOR * underwaterNightLift() : 1.0);
    return max(surfaceBlockLight(s) * L.blockScale + skyAmbientShare(s) * skyIrradiance, floorLight);
}

// water caustics: an animated tiling pattern projected straight down from the surface. The returned factor
// multiplies the direct light; (p + 1) x^p keeps the average energy when the contrast exponent p changes.
float causticFactor(vec3 worldPos, vec3 normal) {
    float frame = mod(floor(frameTimeCounter / CAUSTIC_FRAME_TIME), CAUSTIC_FRAMES);
    vec2 tile = fract(worldPos.xz * CAUSTIC_SCALE);
    float pattern = texture(causticsTex, vec2(tile.x, (tile.y + frame) / CAUSTIC_FRAMES)).r;
    float x = pattern * 2.0 * saturate(normal.y);
    return pow(max(x, 1e-4), CAUSTIC_POWER) * (CAUSTIC_POWER + 1.0);
}
// caustics only while the camera is under water (then everything it sees is lit through the surface)
float submergedCaustics(vec3 worldPos, vec3 normal) {
    #ifdef WATER_CAUSTICS
        if (isEyeInWater == 1) return causticFactor(worldPos, normal);
    #endif
    return 1.0;
}

// ------------------------------------------------------------------ BRDF terms
float ggxDistribution(float NdotH, float alpha2) {
    float t = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
    return alpha2 / (t * t * PI);
}
float smithSchlickG1(float NdotX, float k) { return NdotX / (NdotX * (1.0 - k) + k + 0.0001); }
vec3 fresnelSchlick(vec3 F0, float cosTheta) { return F0 + (1.0 - F0) * pow5(max(1.0 - cosTheta, 0.0)); }
vec3 specularColor(Surface s) { return s.metal * s.albedo + (1.0 - s.metal) * 0.04; }

// ------------------------------------------------------------------ key light
KeyLightResult keyLight(Surface s, Daylight L, vec3 V, float caustics, float transmissionScale) {
    KeyLightResult r = KeyLightResult(vec3(0.0), vec3(0.0), 0.0);
    // a surface the sky light never reaches (sealed caves) gets no sun or moon light either. Not with the camera
    // under water: the game's sky light loses a level per block of water, so every sea floor deeper than 15 blocks
    // read as a sealed cave and the sun never reached it (the target look lights it through the water); there the
    // shadow map alone decides
    if (s.skyLevel < 0.5 / 255.0 && isEyeInWater != 1) return r;
    vec3 N = s.normal, Lk = L.keyDir;
    float subsurface = s.sss * SSS_CONTRIBUTION;
    float NdL = dot(N, Lk);
    // nothing can reach the surface: skip the shadow lookups
    if ((NdL <= 0.0 && subsurface <= 0.0) || dot(L.keyLight, vec3(1.0)) <= 0.0) return r;

    // visibility: shadow map (offset along the geometric normal) and cloud shadow, faded out past the shadow range
    ShadowSample sm = shadowLookup(s.pos, s.flatNormal, 1.0, subsurface > 0.0);
    #ifdef TEXEL_SHADOWS
        float cloud = cloudShadow(snapToTexelCentre(s.pos, s.flatNormal) + cameraPosition, Lk, 0.0);
    #else
        float cloud = cloudShadow(s.pos + cameraPosition, Lk, 1.0);
    #endif
    float visibility = shadowRangeFade(min(cloud, sm.visibility), s.viewDepth);
    float transmitted = sm.transmission;
    if (sm.cascade < 0) { visibility = min(cloud, 1.0); transmitted = 1.0; }
    r.shadow = visibility;

    vec3 radiance = L.keyLight * caustics;
    float NdotL = max(NdL, 0.0), NdotV = max(dot(N, -V), 0.0);
    // wrap lighting: (N.L + w) / (1 + w)^2, used in proportion to the subsurface amount
    float wrapNorm = (DIFFUSE_WRAP + 1.0) * (DIFFUSE_WRAP + 1.0);
    float diffuseTerm = mix(NdotL, max((NdL + DIFFUSE_WRAP) / wrapNorm, 0.0), subsurface);
    float backLight = max((DIFFUSE_WRAP - NdL) / wrapNorm, 0.0) * subsurface * transmissionScale;

    vec3 H = normalize(Lk - V);
    float alpha = max(s.roughness, 0.05); alpha *= alpha;
    float D = ggxDistribution(max(dot(N, H), 0.0), alpha * alpha);
    float k = alpha * 0.5;
    float G = smithSchlickG1(NdotV, k) * smithSchlickG1(NdotL, k);
    vec3 F = fresnelSchlick(specularColor(s), max(dot(-V, H), 0.0));

    vec3 lambert = s.albedo * (1.0 - s.metal) * INV_PI;
    vec3 diffuse = (1.0 - F) * diffuseTerm * lambert;
    vec3 specular = F * D * G / (NdotL * NdotV * 4.0 + 0.0001) * NdotL;
    r.diffuse = (backLight * lambert * transmitted + diffuse * visibility) * radiance;
    r.specular = specular * visibility * radiance;
    return r;
}

// ------------------------------------------------------------------ reflections of the environment
vec3 environmentSpecular(Surface s, Daylight L, vec3 V, vec4 ssr) {
    vec3 env = vec3(0.0);
    #ifdef IBL
        env = probeSample(colortex14, reflect(V, s.normal), probeLevel(s.roughness)) * probeSkyFade(s.skyLevel) * PROBE_REFLECTION_GAIN;
    #endif
    // metals near torches still reflect the block light when the sky probe is darker than it
    vec3 blockSpec = surfaceBlockLight(s) * L.blockScale * BLOCK_LIGHT_REFLECTION;
    vec3 floorSpec = mix(L.ambientFloor, blockSpec, saturate(luminance(blockSpec))) * s.metal;
    if (luminance(env) < luminance(floorSpec)) env = floorSpec;
    env = mix(env, ssr.rgb, saturate(ssr.a));
    vec2 split = texture(brdfLut, vec2(saturate(dot(s.normal, -V)), 1.0 - s.roughness)).rg;
    return env * (specularColor(s) * split.x + split.y);
}

// ------------------------------------------------------------------ complete surface
// direct + ambient + emission, fogged; the environment reflection is added after the fog, scaled by what the fog
// leaves. The froxel volume is applied later, in composite.
vec3 shadeSurface(Surface s, Daylight L, vec3 V, float dist, vec3 skyIrradiance, vec4 ssr, float caustics, out float fogT, out KeyLightResult key) {
    key = keyLight(s, L, V, caustics, 1.0);
    vec3 emission = s.albedo * s.emissive * EMISSIVE_STRENGTH;
    #ifdef COLORED_LIGHT
        // a coloured light source glows in its colour (a white-hot core in an intense red, teal or green
        // halo, through the bloom); warm ones as they were
        if (s.emissive > 0.0) {
            vec4 hue = blockLightHue(s.pos, 0.0, LC_TORCH_HUE, 1.0);
            if (hue.a > 0.0) {
                vec3 c = pow(hue.rgb, vec3(COLORED_LIGHT_SATURATION));
                emission = mix(emission, c * max(emission.r, max(emission.g, emission.b)), hue.a * 0.75);
            }
        }
    #endif
    vec3 col = key.specular + key.diffuse + s.albedo * (1.0 - s.metal) * ambientLight(s, L, skyIrradiance)
             + emission;
    fogT = fogAmount(dist, L);
    col = mix(col, fogTint(V, s.skyLevel, L), fogT);
    return col + environmentSpecular(s, L, V, ssr) * (1.0 - fogT);
}

#endif
