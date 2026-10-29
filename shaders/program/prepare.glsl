// Sky probe passes (see lib/skyprobe.glsl):
//  PREPARE_BASE  level 0: the analytic sky in every direction (the lower hemisphere darkened like ground bounce)
//  PREPARE_CONV  levels 1..7: GGX pre-filtered radiance, importance sampled with a Hammersley sequence [Karis 2013];
//                plus the irradiance texel: cosine-weighted average of the upper hemisphere / pi
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
uniform sampler2D cloudTex;
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
        if (px.x < base.z && px.y < base.w) outProbe = vec4(environmentRadiance(probeUvToDir((vec2(px) + 0.5) / vec2(base.zw)), L), 1.0);
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
                if (d.y > 0.0) sum += probeFetchLevel(colortex14, d, 0) * d.y;
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
