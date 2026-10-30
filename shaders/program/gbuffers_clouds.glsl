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
#if CLOUD_SOLAR_RIM == 1 || CLOUD_MODEL == 1
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
    #if CLOUD_MODEL == 1
        // the target look's cloud colour is the vertex colour (each face's shade: top, the two kinds of side, bottom)
        // x the weather's cloud colour; it takes the ambient and the diffuse light, not the scattered sun
        vec3 faceShade = vec3(abs(N.y) > 0.5 ? (N.y > 0.0 ? 1.0 : 0.7) : (abs(N.x) > 0.5 ? 0.9 : 0.8));
        albedo *= faceShade;   // as the vertex shader passes it (saturate(colour x CloudColor)), no sRGB decode
    #endif
    // the sky's ambient light on the cloud. By day the target look's clouds are white and bright from below too (one
    // sky ambient colour, much stronger and paler than the sky probe's irradiance, which left the undersides a dim
    // blue grey); CLOUD_AMBIENT_GREY takes part of its colour out at any hour (the dawn and dusk clouds of the target
    // look are lilac, not blue), CLOUD_AMBIENT scales it while the sun climbs past CLOUD_DAY_SUN (sine of its
    // elevation): sunrise, sunset and night keep their brightness, and so do the grey clouds of rain and thunder
    float dayLift = smoothstep(CLOUD_DAY_SUN.x, CLOUD_DAY_SUN.y, L.sun.dir.y) * (1.0 - saturate(rainStrength));
    vec3 skyAmbient = probeIrradiance(colortex14) * SKY_IRRADIANCE_GAIN * SKY_INTENSITY * skyAmbientBoost();
    skyAmbient = mix(skyAmbient, vec3(luminance(skyAmbient)), CLOUD_AMBIENT_GREY * (1.0 - saturate(rainStrength)) * smoothstep(-0.05, 0.05, L.sun.dir.y)) * mix(1.0, CLOUD_AMBIENT, dayLift);   // by night the clouds keep the sky's blue
    // by night the target look's clouds stand out lighter than the sky (CLOUD_NIGHT_AMBIENT while the sun is down)
    skyAmbient *= mix(CLOUD_NIGHT_AMBIENT, 1.0, smoothstep(-0.05, 0.05, L.sun.dir.y));
    vec3 col = skyAmbient * albedo;

    float y = clamp((vPlayerPos + cameraPosition - N * 0.02).y - layerBottom, 0.0, CLOUD_THICKNESS);
    float viewPath = min(slabPath(y, V.y), SLAB_PATH_CAP);

    // by night the moon lights a cloud only faintly from the side: in the target look a cloud at midnight is one even
    // dark grey, where the moon's direct light drew bright lilac edges around black undersides
    vec3 keyLight = L.keyLight * mix(CLOUD_MOON_DIRECT, 1.0, smoothstep(-0.05, 0.05, L.sun.dir.y));
    #ifdef CLOUD_LIGHTING
        vec3 Lk = L.keyDir;
        float midY = clamp(y + V.y * viewPath * 0.5, 0.0, CLOUD_THICKNESS);
        float lightPath = min(Lk.y > 1e-4 ? (CLOUD_THICKNESS - midY) / Lk.y : SLAB_PATH_CAP, SLAB_PATH_CAP);
        float g = CLOUD_PHASE_G;
        float den = 1.0 + g * g + 2.0 * g * dot(Lk, -V);
        float phase = (1.0 - g * g) * INV_4PI / (den * sqrt(den));
        col += phase * keyLight * exp(-lightPath * CLOUD_DENSITY) * (1.0 - smoothstep01(saturate(viewPath * 0.5 / LIGHT_FADE)));
        float wrapNorm = (DIFFUSE_WRAP + 1.0) * (DIFFUSE_WRAP + 1.0);
        float front = max((dot(N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
        float back = max((dot(-N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
        float thin = 1.0 - smoothstep01(saturate(viewPath / LIGHT_FADE));
        col += keyLight * (front * albedo * INV_PI + back * albedo * INV_PI * thin);
        #ifdef IBL
            vec3 env = probeSample(colortex14, reflect(V, N), float(PROBE_LEVELS - 1) * 0.75) * PROBE_REFLECTION_GAIN;
            vec2 split = texture(brdfLut, vec2(saturate(dot(N, -V)), 0.0)).rg;
            col += env * (0.04 * split.x + split.y) * CLOUD_REFLECTION;
        #endif
    #else
        col += keyLight * albedo * max(dot(N, L.keyDir), 0.0) * INV_PI;
    #endif

    #if CLOUD_MODEL == 1 && defined CLOUD_LIGHTING && !defined DIM_NETHER && !defined DIM_END
        // The target look's cloud model (CloudsForwardPBR): one pass over the real paths through the cells, from the
        // face to where the view leaves the cloud (neighbours count, a joined cloud is one body) and from the middle
        // of that to where the light leaves it. Scattered sun: phase x light x e^(-light path x density), fading out
        // with the view path; diffuse: wrapped front light + back light fading with the view path; ambient as above.
        // Near the sun the forward lobe lights the whole cloud, edges and body alike; away from it the body keeps the
        // ambient and the thin edges and sunward faces keep the light: the rim comes from the paths, not from a term
        // of its own. It replaces the slab model above (and the rim correction of the other models)
        if (cloudGridKnown() && all(greaterThan(textureSize(cloudTex, 0), ivec2(0)))) {
            vec3 origin = vPlayerPos + cameraPosition - N * 0.02;
            vec3 Lk = L.keyDir;
            float viewPathVV = shiroiCloudExit(origin, V, layerBottom);
            float lightPathVV = shiroiCloudExit(origin + V * (viewPathVV * 0.5), Lk, layerBottom);
            float g = CLOUD_PHASE_G;
            float den = max(1.0 + g * g - 2.0 * g * dot(Lk, V), 0.001);
            float phase = (1.0 - g * g) * INV_4PI / (den * sqrt(den));
            float wrapNorm = (DIFFUSE_WRAP + 1.0) * (DIFFUSE_WRAP + 1.0);
            float front = max((dot(N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
            float back = max((dot(-N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
            vec3 vvCol = skyAmbient * albedo;
            vvCol += phase * keyLight * exp(-lightPathVV * CLOUD_DENSITY) * (1.0 - smoothstep01(saturate(viewPathVV * 0.5 / LIGHT_FADE)));
            vvCol += keyLight * (front * albedo * INV_PI + back * albedo * INV_PI * (1.0 - smoothstep01(saturate(viewPathVV / LIGHT_FADE))));
            #ifdef IBL
                vec3 envVV = probeSample(colortex14, reflect(V, N), float(PROBE_LEVELS - 1) * 0.75) * PROBE_REFLECTION_GAIN;
                vec2 splitVV = texture(brdfLut, vec2(saturate(dot(N, -V)), 0.0)).rg;
                vvCol += envVV * (0.04 * splitVV.x + splitVV.y) * CLOUD_REFLECTION;
            #endif
            col = vvCol;
        }
    #elif CLOUD_SOLAR_RIM == 1
        col += shiroiCloudSolarRim(vPlayerPos + cameraPosition, N, V, layerBottom, L, albedo, vColor.rgb);
    #endif

    // far clouds fade into the sky, and into the fog of falling snow
    float fade = max(saturate(dist / max(far * 2.0, 256.0) - CLOUD_FOG_START), 1.0 - exp(-dist * L.fogDensity));
    col = mix(col, skyRadiance(V, L), fade);
    #if CLOUD_MODEL == 1
        // the target look's clouds have one opacity, the cloud colour's alpha (CloudColor.w): see-through, a cloud
        // behind another shows through it (the game's 0.8)
        outColor = vec4(sanitize(col), CLOUD_ALPHA > 0.0 ? CLOUD_ALPHA : faceAlpha);
    #else
        float transmittance = (1.0 - faceAlpha) * exp(-viewPath * CLOUD_DENSITY * CLOUD_OPACITY);
        outColor = vec4(sanitize(col), 1.0 - transmittance);
    #endif
    outSkyObjects = vec4(0.0);
}
#endif
