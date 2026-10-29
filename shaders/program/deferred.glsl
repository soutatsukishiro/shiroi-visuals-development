// Deferred pass: lights the opaque G-buffer and fills the sky behind it.
// The froxel fog and light shafts come later, in composite after the translucents, as colour x transmittance +
// in-scattered light.
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
out vec2 vUv;
void main() { vUv = gl_MultiTexCoord0.xy; gl_Position = sceneClip(ftransform()); }
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/gbuffer.glsl"
#include "/lib/shading.glsl"
#include "/lib/ssr.glsl"
uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D depthtex0;
in vec2 vUv;

/* RENDERTARGETS: 0,7,2 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outDirect;  // colortex7 from here on: direct light, for the caustics seen through water
layout(location = 2) out vec4 outGlow;    // colortex2 from here on: emissive glow weight for the bloom

vec3 skyBackground(vec3 V, Daylight L) {
    vec3 sky = skyRadiance(V, L);
    #ifdef DIM_END
        sky *= texture(colortex5, sceneUv(vUv)).rgb * END_SKY_GAIN;   // the End sky texture, tinted by the atmosphere colour
    #endif
    return sky;
}

// colour the reflected ray meets in the previous frame (weight in w, 0 when the ray leaves the screen)
vec4 screenReflection(vec3 viewPos, vec3 normal, float roughness) {
    vec3 viewNormal = normalize(mat3(gbufferModelView) * normal);
    vec4 hit = traceScreenReflection(depthtex0, viewPos, viewNormal, roughness, interleavedGradientNoise(gl_FragCoord.xy));
    if (hit.w > 0.0) {
        vec2 prevUv = previousScreenUv(hit.xy, texture(depthtex0, sceneUv(hit.xy)).r);
        if (all(greaterThan(prevUv, vec2(0.0))) && all(lessThan(prevUv, vec2(1.0))))
            return vec4(texture(colortex6, prevUv).rgb, hit.w);
    }
    return vec4(0.0);
}

void main() {
    Daylight L = daylight();
    float depth = texture(depthtex0, sceneUv(vUv)).r;
    vec3 viewPos = rasterToView(vUv, depth);
    vec3 playerPos = viewToPlayer(viewPos);
    float dist = length(playerPos);
    vec3 V = playerPos / max(dist, 1e-5);
    vec4 lighting = texture(colortex3, sceneUv(vUv));

    // nothing written, or only depth (some vanilla sky geometry): sky. The sun, moon and stars of colortex5 are added
    // in composite after the clouds, so a cloud covers them completely.
    if (depth >= 1.0 || lighting.w < 0.25) {
        outColor = vec4(skyBackground(V, L), 1.0);
        outDirect = vec4(0.0);
        outGlow = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    // forward-shaded (entities, hand, block entities, beams, outlines): keep the colour drawn in the gbuffer phase
    // (colortex0 is flipped, so this reads it) plus the overlays
    if (lighting.w < 0.75) {
        outColor = vec4(sanitize(texture(colortex0, sceneUv(vUv)).rgb + texture(colortex7, sceneUv(vUv)).rgb), 1.0);
        outDirect = vec4(0.0);
        outGlow = vec4(materialIdOf(lighting) == MAT_EYES ? 1.0 : 0.0, 0.0, 0.0, 1.0);
        return;
    }

    GBufferTexel g = decodeGBuffer(texture(colortex1, sceneUv(vUv)), texture(colortex2, sceneUv(vUv)), lighting);
    bool hand = g.materialId == MAT_HAND;
    Surface s;
    s.albedo = srgbToLinear(g.albedoSrgb);
    s.metal = g.metal;
    s.sss = g.sss;
    s.roughness = g.roughness;
    s.emissive = g.emissive;
    s.flatNormal = g.geoNormal;
    s.blockLevel = g.lightmap.x;
    s.skyLevel = g.lightmap.y;
    s.normal = g.normal;
    s.pos = playerPos;
    s.viewDepth = hand ? 0.0 : -viewPos.z;

    vec3 skyIrr = skyIrradianceNow();
    vec4 ssr = vec4(0.0);
    #ifdef SSR
        if (s.roughness < SSR_ROUGH_CUTOFF && !hand) ssr = screenReflection(viewPos, s.normal, s.roughness);
    #endif
    float caustics = submergedCaustics(playerPos + cameraPosition, s.normal);

    float fogT;
    KeyLightResult key;
    vec3 col = shadeSurface(s, L, V, dist, skyIrr, ssr, caustics, fogT, key);
    col += texture(colortex7, sceneUv(vUv)).rgb * (1.0 - fogT);           // glint and other additive overlays
    col *= 1.0 + nightVision * 4.0 * (1.0 - s.skyLevel);         // night vision lifts what the sky does not light

    outColor = vec4(sanitize(col), 1.0);
    // without the caustics: composite puts them back only where the surface is seen through water
    outDirect = vec4((key.diffuse + key.specular) * (1.0 - fogT) / max(caustics, 1e-3), 1.0);
    outGlow = vec4(s.emissive * (1.0 - fogT), 0.0, 0.0, 1.0);

    #if DEBUG_VIEW == 1
        outColor = vec4(s.albedo, 1.0);
    #elif DEBUG_VIEW == 2
        outColor = vec4(s.normal * 0.5 + 0.5, 1.0);
    #elif DEBUG_VIEW == 3
        outColor = vec4(vec3(s.roughness), 1.0);
    #elif DEBUG_VIEW == 4
        outColor = vec4(vec3(key.shadow), 1.0);
    #elif DEBUG_VIEW == 7
        outColor = vec4(skyIrr, 1.0);
    #endif
}
#endif
