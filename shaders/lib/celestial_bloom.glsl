// Source weight only: the existing emissive bloom performs all optical spread.
// Read the already occluded celestial buffer, never reconstruct a hidden disc.
#include "/lib/daylight.glsl"
float celestialBloomWeight(vec2 uv, vec3 objects, vec3 scene) {
#if SUN_LIGHT_BLEED != 1 || defined DIM_NETHER || defined DIM_END
    return 0.0;
#else
    if (isEyeInWater != 0) return 0.0;
    #ifdef MOD_COMPAT
        if (mcCompatSkyless()) return 0.0;
    #endif
    float objectLum = luminance(max(objects, vec3(0.0)));
    // Stars remain on their existing bloom path. The angular check identifies
    // the source; it never creates energy outside its actually drawn pixels.
    if (objectLum <= STAR_BRIGHTNESS * STAR_INTENSITY * 1.01) return 0.0;
    vec3 ray = normalize(screenToView(uv, 1.0));
    float sunCone = dot(ray, normalize(sunPosition));
    float moonCone = dot(ray, normalize(moonPosition));
    float sourceWeight = sunCone > 0.97 ? 1.0 : (moonCone > 0.97 ? 0.35 : 0.0);
    float sourceShare = saturate(objectLum / max(luminance(scene), objectLum));
    return sourceWeight * sourceShare;
#endif
}
