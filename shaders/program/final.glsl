// Final pass: white balance, midtone grading, exposure and tone mapping, display gamma.
//  white balance  correlated colour temperature -> chromaticity on the Planckian locus [Krystek 1985 rational
//                 approximation of CIE 1960 u, v] -> xy -> XYZ -> LMS (CAT02) and a von Kries scaling against the
//                 D65 white; applied as one matrix in linear sRGB (sRGB <-> LMS = CAT02 x sRGB primaries, 3 digits)
//  grading        contrast around the average luminance, saturation
//  tone mapping   the "generic" curve of Lottes [GDC 2016, "Advanced Techniques and Optimization of HDR Color
//                 Pipelines"]: peak^a / (b peak^a + c) on the max channel, with his hue-preserving crosstalk; other
//                 classic curves selectable (Reinhard [2002], Hable [GDC 2010], ACES fit [Stephen Hill, MIT])
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
void main() { gl_Position = ftransform(); }
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/exposure.glsl"
uniform sampler2D colortex0;
#if DEBUG_VIEW == 8
    uniform sampler2D colortex3;   // z: material id (the outline diagnosis)
#endif
uniform float biomeKelvin;   // shaders.properties: colour temperature of the biome's grading, smoothed
layout(location = 0) out vec4 outColor;

// u, v (CIE 1960) of a blackbody at T kelvin, Krystek's rational fit
vec2 planckianUv(float T) {
    float T2 = T * T;
    float u = (0.860117733 + 0.000154118257 * T + 1.28641219E-07 * T2) / (1.0 + 0.0008424202 * T + 7.08145137E-07 * T2);
    float v = (0.317398727 + 4.22806261E-05 * T + 4.20481676E-08 * T2) / (1.0 - 2.8974182E-05 * T + 1.61456057E-07 * T2);
    return vec2(u, v);
}
// linear sRGB matrix that white-balances towards (toTemperature == true) or away from the colour of T
mat3 whiteBalance(float T, bool toTemperature) {
    vec2 uv = planckianUv(T);
    float den = 2.0 * uv.x - 8.0 * uv.y + 4.0;
    vec2 xy = vec2(3.0 * uv.x, 2.0 * uv.y) / den;
    vec3 XYZ = vec3(xy.x / xy.y, 1.0, (1.0 - xy.x - xy.y) / xy.y);
    const mat3 XYZ_TO_LMS = mat3(0.7328, -0.7036, 0.003, 0.4296, 1.6975, 0.0136, -0.1624, 0.0061, 0.9834);   // CAT02
    const vec3 D65_LMS = vec3(0.949252963, 1.03541911, 1.08718348);
    vec3 lms = XYZ_TO_LMS * XYZ;
    vec3 gain = toTemperature ? lms * vec3(1.05346, 0.9657925, 0.919808) : D65_LMS / lms;   // 1 / D65_LMS
    const mat3 RGB_TO_LMS = mat3(0.39, 0.071, 0.023, 0.55, 0.963, 0.128, 0.009, 0.001, 0.936);
    const mat3 LMS_TO_RGB = mat3(2.859, -0.21, -0.042, -1.629, 1.158, -0.118, -0.025, 0.0, 1.069);
    vec3 cR = gain * RGB_TO_LMS[0], cG = gain * RGB_TO_LMS[1], cB = gain * RGB_TO_LMS[2];
    vec3 r0 = vec3(LMS_TO_RGB[0].x, LMS_TO_RGB[1].x, LMS_TO_RGB[2].x);
    vec3 r1 = vec3(LMS_TO_RGB[0].y, LMS_TO_RGB[1].y, LMS_TO_RGB[2].y);
    vec3 r2 = vec3(LMS_TO_RGB[0].z, LMS_TO_RGB[1].z, LMS_TO_RGB[2].z);
    return transpose(mat3(vec3(dot(r0, cR), dot(r0, cG), dot(r0, cB)),
                          vec3(dot(r1, cR), dot(r1, cG), dot(r1, cB)),
                          vec3(dot(r2, cR), dot(r2, cG), dot(r2, cB))));
}

// Lottes' curve: contrast a, white point hdrMax, mid grey midIn -> midOut (with d = 1)
vec3 tonemapLottes(vec3 x) {
    float a = TONEMAP_CONTRAST;
    float hdrMax = TONEMAP_HDR_MAX, midIn = 0.18, midOut = TONEMAP_MID_OUT;
    float m = pow(midIn, a), H = pow(hdrMax, a);
    float b = (H * midOut - m) / ((H - m) * midOut);
    float c = (H * m - H * m * midOut) / ((H - m) * midOut);
    float crossSaturation = 16.0 * a;
    float peak = max(max(x.r, x.g), max(x.b, 1e-6));
    vec3 ratio = max(x, 0.0) / peak;
    float pa = pow(peak, a);
    float mapped = pa / (b * pa + c);
    // crosstalk: bright colours move towards white
    ratio = pow(max(ratio, 1e-6), vec3(1.0 / crossSaturation));
    ratio = mix(ratio, vec3(1.0), pow(saturate(mapped), TONEMAP_CROSSTALK));
    ratio = pow(ratio, vec3(crossSaturation));
    return mapped * ratio;
}
vec3 tonemapClassic(vec3 x, int op, float white) {
    if (op == 0) return x / (x + 1.0);                                          // Reinhard
    if (op == 1) return x * (1.0 + x / (white * white)) / (1.0 + x);             // extended Reinhard
    if (op == 2) { float l = luminance(x); float t = l * (1.0 + l / (white * white)) / (1.0 + l); return x * (t / max(l, 1e-6)); }
    if (op == 3) {                                                              // Hable's filmic curve
        vec3 h = ((x * 2.0) * (x * 0.3 + 0.05) + 0.004) / ((x * 2.0) * (x * 0.3 + 0.5) + 0.06) - 0.06666666;
        float w = white * white;
        float hw = (w * (w * 0.15 + 0.05) + 0.004) / (w * (w * 0.15 + 0.5) + 0.06) - 0.06666666;
        return h / hw;
    }
    // ACES fitted RRT + ODT, Stephen Hill (BakingLab, MIT License, Copyright (c) 2016 MJP: see THIRD_PARTY_NOTICES.md)
    vec3 v = vec3(dot(vec3(0.59719, 0.35458, 0.04823), x), dot(vec3(0.076, 0.90834, 0.01566), x), dot(vec3(0.0284, 0.13383, 0.83777), x));
    v = (v * (v + 0.0245786) - 9.0537E-05) / (v * (v * 0.983729 + 0.432951) + 0.238081);
    return saturate(vec3(dot(vec3(1.60475, -0.53108, -0.07367), v), dot(vec3(-0.10208, 1.10813, -0.00605), v), dot(vec3(-0.00327, -0.07276, 1.07602), v)));
}

void main() {
    vec3 col = texelFetch(colortex0, ivec2(gl_FragCoord.xy), 0).rgb;
    #if DEBUG_VIEW >= 1 && DEBUG_VIEW <= 5 || DEBUG_VIEW == 7   // raw views (8, the outline diagnosis, keeps the image)
        outColor = vec4(linearToSrgb(col), 1.0);
        return;
    #endif
    #ifdef AUTO_EXPOSURE
        float avg = clamp(sceneAverageLuminance(), EXPOSURE_AVG_CLAMP.x, EXPOSURE_AVG_CLAMP.y);
        #if !defined DIM_NETHER && !defined DIM_END
            avg = max(avg, duskExposureFloor());   // around sunset and sunrise (program/exposure.glsl EXP_AVERAGE)
        #endif
    #else
        float avg = 0.18;
    #endif
    #ifdef COLOR_TEMPERATURE_ON
        // the pale garden is graded colder (9000 K); the other biomes by the families (biomeKelvin,
        // shaders.properties: snowy biomes 10000 K, taigas 9000 K, jungles and savannas 4800 K, deserts 4400 K, ...;
        // 0 where the custom uniform is not available). BIOME_GRADING 1 grades the whole day as intended,
        // 2 only around sunrise and sunset (the earlier look of deserts and badlands)
        float kelvin = mix(float(COLOR_TEMPERATURE), 9000.0, saturate(paleGardenWeight));
        #if !defined DIM_NETHER && !defined DIM_END && BIOME_GRADING > 0
            #if BIOME_GRADING == 2
                float sunHeight = normalize(mat3(gbufferModelViewInverse) * sunPosition).y;
                float gradeWeight = 1.0 - smoothstep01(saturate(abs(sunHeight) / BIOME_GRADE_SUN_HEIGHT));
            #else
                float gradeWeight = 1.0;
            #endif
            // the biome's offset from the neutral 6500 K, in mireds (1e6 / K: even steps of perceived warmth), so a
            // white balance set in the options moves along
            float biomeK = biomeKelvin > 1000.0 ? biomeKelvin : 6500.0;
            if (sulfurCavesWeight > 0.0) biomeK = 1.0e6 / mix(1.0e6 / biomeK, 1.0e6 / 4800.0, saturate(sulfurCavesWeight));   // sulfur caves: warmish
            if (biomeK != 6500.0) kelvin = 1.0e6 / (1.0e6 / kelvin + (1.0e6 / biomeK - 1.0e6 / 6500.0) * gradeWeight);
        #endif
        col = whiteBalance(kelvin, true) * col;
    #endif
    // contrast around the average luminance, then saturation
    col = pow(max(col, 0.0) / avg, vec3(GRADE_CONTRAST)) * avg;
    col = max(mix(vec3(luminance(col)), col, GRADE_SATURATION), 0.0);

    // camera inside a medium: the water kept darker than the auto exposure would make it (a deep blue, not a pale one),
    // powder snow brighter (nearly white, as in vanilla)
    float mediumEv = isEyeInWater == 1 ? UNDERWATER_EV : (isEyeInWater == 3 ? POWDER_SNOW_EV : 0.0);
    float exposure = 0.18 / avg * exp2(EXPOSURE_EV + mediumEv);
    vec3 x = col * exposure;
    #if TONEMAP_OPERATOR == 5
        vec3 t = tonemapLottes(x);
    #else
        vec3 t = tonemapClassic(x, TONEMAP_OPERATOR, exposure);
    #endif
    vec3 display = pow(max(t, 0.0), vec3(1.0 / GRADE_GAMMA));
    #if DEBUG_VIEW == 6
        display = vec3(log2(avg) / 20.0 + 0.3);
    #elif DEBUG_VIEW == 8
        // outline diagnosis: cyan where the mark of gbuffers_line (MAT_OUTLINE in colortex3) reached the end
        if (int(texture(colortex3, sceneUv(gl_FragCoord.xy / vec2(viewWidth, viewHeight))).z * 255.0 + 0.5) == MAT_OUTLINE) display = mix(display, vec3(0.0, 1.0, 1.0), 0.6);
    #endif
    // triangular dither of +-1 level before the 8 bit output: a wide, smooth gradient (the glow around the sun, a clear
    // sky) went into visible rings of equal value
    vec2 q = gl_FragCoord.xy + float(frameCounter % 64) * vec2(5.588238, 3.15);
    float n1 = fract(52.9829189 * fract(dot(q, vec2(0.06711056, 0.00583715))));
    float n2 = fract(52.9829189 * fract(dot(q + vec2(17.0, 31.0), vec2(0.06711056, 0.00583715))));
    display += (n1 + n2 - 1.0) / 255.0;
    outColor = vec4(clamp(display, 0.0, 1.0), 1.0);
}
#endif
