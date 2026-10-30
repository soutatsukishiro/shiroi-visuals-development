// Sky probe passes (see lib/skyprobe.glsl):
//  PREPARE_BASE  level 0: the analytic sky in every direction (the lower hemisphere darkened like ground bounce),
//                with the clouds in it as the target look draws them into its sky probe (CloudsForwardPBR,
//                ForwardPBRTransparentSkyProbe): reflections of clouds come from here, soft, not from the screen
//  PREPARE_CONV  levels 1..7: GGX pre-filtered radiance, importance sampled with a Hammersley sequence [Karis 2013];
//                plus the irradiance texel: cosine-weighted average of the upper analytic sky / pi (without the
//                clouds: the ambient light of the world stays the sky's)
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
void main() { gl_Position = ftransform(); }
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/skymodel.glsl"
#define PROBE_SAMPLER
#include "/lib/skyprobe.glsl"
uniform sampler2D colortex14;
// The cloud texture is the game's own (customTexture minecraft:...), which Iris loads the first time a program that
// samples it is bound. On MC 26 the gbuffers programs are bound inside the game's render passes, where loading a
// texture throws ("Close the existing render pass before performing additional commands", a crash). Iris draws the
// prepare passes itself, outside those passes and before the world in every frame, so this one samples the texture
// (behind a condition that is never true, which the compiler cannot remove) to have it loaded here first.
#include "/lib/clouds.glsl"
/* RENDERTARGETS: 14 */
layout(location = 0) out vec4 outProbe;

vec3 environmentRadiance(vec3 d, Daylight L) {
    vec3 c = skyRadiance(d, L);
    #ifdef DIM_END
        c *= END_SKY_TEXTURE_MEAN;   // the End sky as it is seen, with its texture (lib/look.glsl)
    #endif
    // no terrain is rendered into the probe: below the horizon keep the horizon colour, darkened like ground bounce
    if (d.y < 0.0) c *= mix(1.0, 0.35, saturate(-d.y * 4.0));
    return c;
}

#if defined PREPARE_BASE && defined CLOUD_PROBE && !defined DIM_NETHER && !defined DIM_END
// the sky's irradiance / pi from the analytic sky (the probe being written cannot be read here)
vec3 analyticSkyIrradiance(Daylight L) {
    vec3 sum = vec3(0.0);
    for (int i = 0; i < 16; i++) {
        float z = (float(i) + 0.5) / 16.0;   // cos of the zenith angle, uniform: the cosine weight is in the density
        float a = 2.399963 * float(i);
        float r = sqrt(1.0 - z * z);
        sum += skyRadiance(vec3(r * cos(a), z, r * sin(a)), L);
    }
    return sum / 16.0;
}

// the cloud layer seen along d from the camera, lit as program/gbuffers_clouds.glsl lights a top or bottom face
// (sky ambient, the key light scattered through the slab, wrapped diffuse; no rim, no reflection): colour, coverage
vec4 probeCloud(vec3 d, Daylight L, vec3 skyIrradiance) {
    float bottom = CLOUD_HEIGHT, camY = cameraPosition.y;
    if (!cloudGridKnown() || abs(d.y) < 0.01 || (camY > bottom && camY < bottom + CLOUD_THICKNESS)) return vec4(0.0);
    bool below = camY <= bottom;
    float t = ((below ? bottom : bottom + CLOUD_THICKNESS) - camY) / d.y;
    if (t <= 0.0) return vec4(0.0);
    vec2 grid = cloudGridPos(cameraPosition.xz + d.xz * t) / CLOUD_CELL;
    if (!cloudCell(ivec2(floor(grid)))) return vec4(0.0);

    vec3 albedo = vec3(1.0);
    albedo = mix(albedo, vec3(RAIN_CLOUD_GREY / 255.0), rainStrength * CLOUD_WEATHER_WEIGHT);
    albedo = mix(albedo, vec3(STORM_CLOUD_GREY / 255.0), thunderStrength * CLOUD_WEATHER_WEIGHT * (1.0 - saturate(snowWeight)));
    albedo = srgbToLinear(saturate(albedo));
    float dayLift = smoothstep(CLOUD_DAY_SUN.x, CLOUD_DAY_SUN.y, L.sun.dir.y) * (1.0 - saturate(rainStrength));
    vec3 skyAmbient = skyIrradiance * SKY_IRRADIANCE_GAIN * SKY_INTENSITY * skyAmbientBoost();
    skyAmbient = mix(skyAmbient, vec3(luminance(skyAmbient)), CLOUD_AMBIENT_GREY * (1.0 - saturate(rainStrength)) * smoothstep(-0.05, 0.05, L.sun.dir.y)) * mix(1.0, CLOUD_AMBIENT, dayLift);   // by night the clouds keep the sky's blue
    skyAmbient *= mix(CLOUD_NIGHT_AMBIENT, 1.0, smoothstep(-0.05, 0.05, L.sun.dir.y));
    vec3 col = skyAmbient * albedo;
    vec3 keyLight = L.keyLight * mix(CLOUD_MOON_DIRECT, 1.0, smoothstep(-0.05, 0.05, L.sun.dir.y));
    vec3 N = vec3(0.0, below ? -1.0 : 1.0, 0.0);
    float viewPath = min(CLOUD_THICKNESS / abs(d.y), 12.0);
    #ifdef CLOUD_LIGHTING
        vec3 Lk = L.keyDir;
        float y = below ? 0.0 : CLOUD_THICKNESS;
        float midY = clamp(y + d.y * viewPath * 0.5, 0.0, CLOUD_THICKNESS);
        float lightPath = min(Lk.y > 1e-4 ? (CLOUD_THICKNESS - midY) / Lk.y : 12.0, 12.0);
        float g = CLOUD_PHASE_G;
        float den = 1.0 + g * g + 2.0 * g * dot(Lk, -d);
        float phase = (1.0 - g * g) * INV_4PI / (den * sqrt(den));
        col += phase * keyLight * exp(-lightPath * CLOUD_DENSITY) * (1.0 - smoothstep01(saturate(viewPath * 0.5 / 8.0)));
        float wrapNorm = (DIFFUSE_WRAP + 1.0) * (DIFFUSE_WRAP + 1.0);
        float front = max((dot(N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
        float back = max((dot(-N, Lk) + DIFFUSE_WRAP) / wrapNorm, 0.0);
        float thin = 1.0 - smoothstep01(saturate(viewPath / 8.0));
        col += keyLight * (front * albedo * INV_PI + back * albedo * INV_PI * thin);
    #else
        col += keyLight * albedo * max(dot(N, L.keyDir), 0.0) * INV_PI;
    #endif
    float fade = max(saturate(t / max(far * 2.0, 256.0) - CLOUD_FOG_START), 1.0 - exp(-t * L.fogDensity));
    col = mix(col, skyRadiance(d, L), fade);
    float coverage = 1.0 - 0.2 * exp(-viewPath * CLOUD_DENSITY * CLOUD_OPACITY);   // the vanilla faces' alpha 0.8
    return vec4(col, coverage);
}
#endif

// Van der Corput radical inverse in base 2 (bit reversal)
float radicalInverse(uint b) {
    b = (b << 16u) | (b >> 16u);
    b = ((b & 0x55555555u) << 1u) | ((b & 0xAAAAAAAAu) >> 1u);
    b = ((b & 0x33333333u) << 2u) | ((b & 0xCCCCCCCCu) >> 2u);
    b = ((b & 0x0F0F0F0Fu) << 4u) | ((b & 0xF0F0F0F0u) >> 4u);
    b = ((b & 0x00FF00FFu) << 8u) | ((b & 0xFF00FF00u) >> 8u);
    return float(b) * 2.32830644e-10;
}

void main() {
    if (frameCounter < 0) { outProbe = texelFetch(cloudTex, ivec2(0), 0); return; }   // binds cloudTex, see above
    ivec2 px = ivec2(gl_FragCoord.xy);
    Daylight L = daylight();
    ivec4 base = probeLevelRect(0);
    #ifdef PREPARE_BASE
        if (px.x < base.z && px.y < base.w) {
            vec3 d = probeUvToDir((vec2(px) + 0.5) / vec2(base.zw));
            vec3 c = environmentRadiance(d, L);
            #if defined CLOUD_PROBE && !defined DIM_NETHER && !defined DIM_END
                // 2 x 2 directions inside the texel: soft cloud edges, as the geometry the target look draws into its
                // probe (one direction per texel turned every cell edge into a hard step in the reflections)
                vec3 irr = analyticSkyIrradiance(L);
                vec4 cloud = vec4(0.0);
                for (int k = 0; k < 4; k++) {
                    vec2 o = vec2(float(k & 1), float(k >> 1)) * 0.5 - 0.25;
                    vec4 s = probeCloud(probeUvToDir((vec2(px) + 0.5 + o) / vec2(base.zw)), L, irr);
                    cloud += vec4(s.rgb * s.a, s.a);
                }
                cloud *= 0.25;
                c = c * (1.0 - cloud.a) + cloud.rgb;
            #endif
            outProbe = vec4(c, 1.0);
        }
        else outProbe = vec4(0.0);
    #else
        if (px.x < base.z && px.y < base.w) { outProbe = texelFetch(colortex14, px, 0); return; }
        if (px == PROBE_IRRADIANCE_TEXEL) {
            // uniform sphere samples, upper hemisphere weighted by cos: E / pi
            const int N = 256;
            vec3 sum = vec3(0.0);
            for (int i = 0; i < N; i++) {
                float z = 1.0 - 2.0 * ((float(i) + 0.5) / float(N));
                float r = sqrt(max(1.0 - z * z, 0.0));
                float a = 2.0 * PI * radicalInverse(uint(i));
                vec3 d = vec3(r * cos(a), z, r * sin(a));
                if (d.y > 0.0) sum += environmentRadiance(d, L) * d.y;   // the sky without the clouds of level 0
            }
            outProbe = vec4(sum * (4.0 * PI / float(N)) * INV_PI, 1.0);
            return;
        }
        int level = -1;
        for (int l = 1; l < PROBE_LEVELS; l++) {
            ivec4 r = probeLevelRect(l);
            if (px.x >= r.x && px.y >= r.y && px.x < r.x + r.z && px.y < r.y + r.w) { level = l; break; }
        }
        if (level < 0) { outProbe = vec4(0.0); return; }
        ivec4 rect = probeLevelRect(level);
        vec3 N = probeUvToDir((vec2(px - rect.xy) + 0.5) / vec2(rect.zw));
        float alpha = float(level) / float(PROBE_LEVELS - 1);
        alpha *= alpha;
        float alpha2 = alpha * alpha;
        // tangent frame around N
        vec3 helper = abs(N.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
        vec3 T = normalize(cross(helper, N));
        vec3 B = cross(N, T);
        const int SAMPLES = 64;
        vec3 sum = vec3(0.0);
        float weight = 0.0;
        for (int i = 0; i < SAMPLES; i++) {
            // GGX half vector for the Hammersley point (i / N, radicalInverse(i)), reflected around it
            float u = radicalInverse(uint(i));
            float phi = float(i) / float(SAMPLES) * 6.28318548;
            float cos2 = (1.0 - u) / ((alpha2 - 1.0) * u + 1.0);
            float cosT = sqrt(cos2), sinT = sqrt(1.0 - cos2);
            vec3 H = T * (sinT * cos(phi)) + B * (sinT * sin(phi)) + N * cosT;
            vec3 dir = 2.0 * dot(N, H) * H - N;
            float NdotL = saturate(dot(N, dir));
            if (NdotL > 0.0) { sum += probeFetchLevel(colortex14, dir, 0) * NdotL; weight += NdotL; }
        }
        outProbe = vec4(sum / max(weight, 0.001), 1.0);
    #endif
}
#endif
