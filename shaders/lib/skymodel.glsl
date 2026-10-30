#ifndef SKYMODEL_GLSL
#define SKYMODEL_GLSL
// Sky radiance and distance fog colour (the same function: fog takes the colour of the sky behind it).
//  - molecular part: a zenith -> horizon colour gradient, lit by both celestial bodies through the Rayleigh phase
//    function 3/4 (1 + cos^2) [Rayleigh 1871; e.g. Nishita et al. 1993]
//  - halo: a forward-scattering lobe around each body, a Henyey-Greenstein phase function with g = 0.9
//    [Henyey & Greenstein 1941] evaluated on a sharpened cosine cos^n, faded out above the horizon band
#include "/lib/daylight.glsl"

float rayleighPhase(float c) { return 0.75 * (1.0 + c * c); }

// (1 - g^2)^2 / (1 + g^2 - 2 g c)^1.5 for g = 0.9 (the Henyey-Greenstein lobe without its 1/4pi, scaled by 1 - g^2)
float haloPhase(float c) {
    float x = 1.81 - 1.8 * c;
    return 0.0361 / (x * sqrt(x));
}

// 1 at the horizon, 0 at "span" above it, cubic ease: how much of the horizon colour remains at an elevation
float elevationFade(float h, float span) {
    float f = 1.0 - smoothstep01(saturate(h / span));
    return f * f * f;
}

vec3 skyRadiance(vec3 dir, Daylight L) {
#ifdef MOD_COMPAT
    if (mcCompatSkyless()) return mcCompatDimensionFog();
#endif

    float h = dir.y - L.rimBase;
    vec3 gradient = mix(L.skyTop, L.skyRim, elevationFade(h, L.rimSpan)) * L.rayleigh * INV_4PI;
    Celestial bodies[2] = Celestial[2](L.sun, L.moon);
    float molecular = 0.0;
    vec3 halos = vec3(0.0);
    for (int i = 0; i < 2; i++) {
        float c = dot(dir, bodies[i].dir);
        molecular += rayleighPhase(c) * bodies[i].lux * (i == 1 ? MOON_SKY_GAIN : 1.0);   // the moonlit sky as bright as the target look's
        float lobe = c > 0.0 ? pow(c, L.haloExponent) : 0.0;   // pow(0, 0) is undefined
        halos += bodies[i].tint * (bodies[i].lux * bodies[i].halo * SUN_HALO_STRENGTH * lobe * haloPhase(lobe));
    }
    return gradient * molecular + halos * (elevationFade(h, L.haloSpan) * L.skyRim * INV_4PI);
}

// share of a surface hidden by the distance fog: a linear ramp over the last part of the render distance, and the
// exponential (Beer-Lambert) fog of falling snow over the whole distance
float fogAmount(float dist, Daylight L) {
    return max(saturate((dist / L.fogDistance - L.fogStart) * L.fogInvLength), 1.0 - exp(-dist * L.fogDensity));
}

// fog colour: the sky colour where the sky is visible (at the surface or at the camera), cave fog elsewhere
vec3 fogTint(vec3 dir, float skyVisibility, Daylight L) {
    vec3 sky = skyRadiance(dir, L);
    #ifdef DIM_END
        sky *= END_SKY_TEXTURE_MEAN * END_SKY_GAIN;   // the End sky as it is seen, with its texture
    #endif
    return mix(L.caveFog, sky, max(skyVisibility, L.eyeSky));
}

#endif
