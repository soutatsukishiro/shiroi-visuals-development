// Clouds: the Java cloud geometry (12x4x12 cells), lit as a continuous 4-block slab.
//  * opacity: the vanilla face alpha, times Beer-Lambert extinction along the view path through the slab
//  * light: sky ambient + single scattering of the key light (Henyey-Greenstein phase, Beer-Lambert towards the light
//    from the middle of the view path) + wrapped diffuse and a back-light term + a faint sky reflection
//  * horizontal paths are capped at one cell: without adjacency information every cell would otherwise look
//    bright at its edges and dark in the middle
//  * clouds also clear colortex5 (blend off), so the sun, moon and stars behind them are never added
//  * the clouds also feed the cloud tracking of lib/clouds.glsl (which also says where the geometry comes from)
#include "/lib/common.glsl"
#include "/lib/clouds.glsl"

#ifdef VERTEX_SHADER
out vec4 vColor;
out vec3 vPlayerPos;
out vec3 vNormal;
void main() {
    vColor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPos = (gbufferModelViewInverse * viewPos).xyz;
    vNormal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    cloudTrackVertex(vPlayerPos + cameraPosition, vNormal);
    gl_Position = taaJitterClip(gl_ProjectionMatrix * viewPos);
}
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/skymodel.glsl"
#if CLOUD_SOLAR_RIM == 1
#include "/lib/cloud_solar_rim.glsl"
#endif
#define PROBE_SAMPLER
#include "/lib/skyprobe.glsl"
uniform sampler2D colortex14;
uniform sampler2D brdfLut;
in vec4 vColor;
in vec3 vPlayerPos;
in vec3 vNormal;
/* RENDERTARGETS: 0,5 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outSkyObjects;

const float SLAB_PATH_CAP = 12.0;   // longest path counted through the slab (one cell)
const float LIGHT_FADE = 8.0;       // path length over which the scattering and back light fade out

// path through the slab from height y (0 at the bottom) along d
float slabPath(float y, float dy) {
    return dy > 1e-4 ? (CLOUD_THICKNESS - y) / dy : (dy < -1e-4 ? y / -dy : SLAB_PATH_CAP);
}

void main() {
    sceneGuard();

#ifdef MOD_COMPAT
    if (mcCompatSkyless()) discard;
#endif
    float faceAlpha = vColor.a;
    vec3 N = normalize(vNormal);
    // from outside the layer only front faces count (back faces would blend through in draw order: a lattice)
    float layerBottom = CLOUD_HEIGHT;
    bool insideLayer = cameraPosition.y > layerBottom && cameraPosition.y < layerBottom + CLOUD_THICKNESS;
    if (!gl_FrontFacing && !insideLayer) discard;
    Daylight L = daylight();
    float dist = length(vPlayerPos);
    vec3 V = vPlayerPos / dist;
    // white clouds, grey with rain, dark with thunder (the vanilla vertex colour already carries its own day dimming);
    // where it snows thunder leaves them as they are under the snow, like its sky
    vec3 albedo = vec3(1.0);
    albedo = mix(albedo, vec3(RAIN_CLOUD_GREY / 255.0), rainStrength * CLOUD_WEATHER_WEIGHT);
    albedo = mix(albedo, vec3(STORM_CLOUD_GREY / 255.0), thunderStrength * CLOUD_WEATHER_WEIGHT * (1.0 - saturate(snowWeight)));
    albedo = srgbToLinear(saturate(albedo));
    vec3 col = probeIrradiance(colortex14) * SKY_IRRADIANCE_GAIN * SKY_INTENSITY * albedo;

    float y = clamp((vPlayerPos + cameraPosition - N * 0.02).y - layerBottom, 0.0, CLOUD_THICKNESS);
    float viewPath = min(slabPath(y, V.y), SLAB_PATH_CAP);

    #ifdef CLOUD_LIGHTING
        vec3 Lk = L.keyDir;
        float midY = clamp(y + V.y * viewPath * 0.5, 0.0, CLOUD_THICKNESS);
        float lightPath = min(Lk.y > 1e-4 ? (CLOUD_THICKNESS - midY) / Lk.y : SLAB_PATH_CAP, SLAB_PATH_CAP);
        float g = CLOUD_PHASE_G;
        float den = 1.0 + g * g + 2.0 * g * dot(Lk, -V);
        float phase = (1.0 - g * g) * INV_4PI / (den * sqrt(den));
        col += phase * L.keyLight * exp(-lightPath * CLOUD_DENSITY) * (1.0 - smoothstep01(saturate(viewPath * 0.5 / LIGHT_FADE)));
        float wrapNorm = (DIFFUSE_WRAP + 1.0) * (DIFFUSE_WRAP + 1.0);
        float front = max((dot(N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
        float back = max((dot(-N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
        float thin = 1.0 - smoothstep01(saturate(viewPath / LIGHT_FADE));
        col += L.keyLight * (front * albedo * INV_PI + back * albedo * INV_PI * thin);
        #ifdef IBL
            vec3 env = probeSample(colortex14, reflect(V, N), float(PROBE_LEVELS - 1) * 0.75) * PROBE_REFLECTION_GAIN;
            vec2 split = texture(brdfLut, vec2(saturate(dot(N, -V)), 0.0)).rg;
            col += env * (0.04 * split.x + split.y) * CLOUD_REFLECTION;
        #endif
    #else
        col += L.keyLight * albedo * max(dot(N, L.keyDir), 0.0) * INV_PI;
    #endif

    #if CLOUD_SOLAR_RIM == 1
        col += shiroiCloudSolarRim(vPlayerPos + cameraPosition, N, V, layerBottom, L, albedo, vColor.rgb);
    #endif

    // far clouds fade into the sky, and into the fog of falling snow
    float fade = max(saturate(dist / max(far * 2.0, 256.0) - CLOUD_FOG_START), 1.0 - exp(-dist * L.fogDensity));
    col = mix(col, skyRadiance(V, L), fade);
    float transmittance = (1.0 - faceAlpha) * exp(-viewPath * CLOUD_DENSITY * CLOUD_OPACITY);
    outColor = vec4(sanitize(col), 1.0 - transmittance);
    outSkyObjects = vec4(0.0);
}
#endif
