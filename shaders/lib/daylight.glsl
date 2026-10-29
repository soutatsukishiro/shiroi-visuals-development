#ifndef DAYLIGHT_GLSL
#define DAYLIGHT_GLSL
// State of the sky lights for the current frame: the sun and the moon as two "celestial bodies" (direction, tint,
// illuminance, halo), the shadow-casting key light, the sky gradient colours, fog range and ambient terms.
// Everything is driven by the day phase and the look tables of lib/look.glsl.
#include "/lib/common.glsl"
#include "/lib/look.glsl"

uniform float thunderStrength;
uniform float endFlashIntensity;   // Iris 1.11: 0..1 while an End flash lights the sky

// A day curve of lib/look.glsl (DAY_SAMPLES values, one every 1/DAY_STEPS of the day) at phase X, interpolated
#define DAYCURVE(VAL, X, R) { \
    float f_ = saturate(X) * float(DAY_STEPS); int i_ = min(int(f_), DAY_STEPS - 1); \
    R = mix(VAL[i_], VAL[i_ + 1], f_ - float(i_)); }

struct Celestial {
    vec3 dir;     // player space, unit
    vec3 tint;    // linear colour
    float lux;    // illuminance
    float halo;   // strength of the forward-scattering halo around it
};

struct Daylight {
    Celestial sun, moon;
    vec3 keyDir;          // direction of the light Iris renders the shadow map from
    vec3 keyLight;        // its colour x illuminance (0 under rain)
    vec3 skyTop, skyRim;  // zenith and horizon colours (linear)
    float rayleigh;       // strength of the sky gradient
    float haloExponent;   // lobe exponent of the halos
    float rimBase, rimSpan, haloSpan;   // elevation ramps of the horizon colour and of the halo
    vec3 ambientFloor;
    float blockScale;     // block light multiplier
    float fogStart, fogInvLength, fogDistance;
    float fogDensity;     // extra exponential fog (m^-1): falling snow
    vec3 caveFog;
    float eyeSky;         // sky light at the camera (eyeBrightnessSmooth)
};

// 0 = noon, 0.25 = sunset, 0.5 = midnight, 0.75 = sunrise (Iris sunAngle is 0 at sunrise)
float dayPhase() { return fract(sunAngle - 0.25); }

Daylight daylight() {
    Daylight L;
    float d = dayPhase();
    float wet = rainStrength;
    float clearSky = 1.0 - wet;   // no direct sun or moon light while it rains

    float sunLux, moonLux, rayleigh, halo, haloWidth, rimHeight, haloHeight;
    vec3 sunTint, top, rim;
    DAYCURVE(SUN_LUX, d, sunLux)
    DAYCURVE(MOON_LUX, d, moonLux)
    DAYCURVE(SUN_TINT, d, sunTint)
    DAYCURVE(SKY_TOP, d, top)
    DAYCURVE(SKY_RIM, d, rim)
    DAYCURVE(RAYLEIGH, d, rayleigh)
    DAYCURVE(HALO_STRENGTH, d, halo)
    DAYCURVE(HALO_WIDTH, d, haloWidth)
    DAYCURVE(RIM_HEIGHT, d, rimHeight)
    DAYCURVE(HALO_HEIGHT, d, haloHeight)
    top /= 255.0; rim /= 255.0;
    vec3 sunTintLin = srgbToLinear(sunTint / 255.0);
    vec3 moonTintLin = srgbToLinear(MOON_TINT / 255.0);

    #if !defined DIM_NETHER && !defined DIM_END
        float pale = saturate(paleGardenWeight);
        if (pale > 0.0) {
            float paleLux; vec3 paleTop, paleRim;
            DAYCURVE(PALE_SUN_LUX, d, paleLux)
            DAYCURVE(PALE_SKY_TOP, d, paleTop)
            DAYCURVE(PALE_SKY_RIM, d, paleRim)
            sunLux = mix(sunLux, paleLux, pale);
            sunTintLin = mix(sunTintLin, srgbToLinear(PALE_SUN_TINT / 255.0), pale);
            moonTintLin = mix(moonTintLin, srgbToLinear(PALE_MOON_TINT / 255.0), pale);
            top = mix(top, paleTop / 255.0, pale);
            rim = mix(rim, paleRim / 255.0, pale);
        }
    #endif

    // rain hides the discs (gbuffers_sky), the halo and the direct light, but the overcast sky keeps scattering the
    // light of the hidden sun: with the illuminance itself scaled by the rain the sky, and all the ambient light that
    // comes from it, went black at noon (a rainy day looked like the night)
    L.sun = Celestial(normalize(mat3(gbufferModelViewInverse) * sunPosition), sunTintLin, sunLux, halo * clearSky);
    L.moon = Celestial(normalize(mat3(gbufferModelViewInverse) * moonPosition), moonTintLin, moonLux, 0.0);

    // Iris casts shadows from the sun while it is up and from the moon otherwise
    bool sunUp = d < 0.25 || d > 0.75;
    L.keyDir = normalize(mat3(gbufferModelViewInverse) * shadowLightPosition);
    L.keyLight = (sunUp ? sunTintLin * sunLux : moonTintLin * moonLux) * clearSky;

    // overcast: the sky turns grey with rain, darker with thunder. Where it snows it keeps a blue-lavender zenith and a
    // pink horizon (lib/look.glsl), with thunder too
    float snow = 0.0;
    #if !defined DIM_NETHER && !defined DIM_END
        snow = saturate(snowWeight);
    #endif
    vec3 clearTop = top, clearRim = rim;
    // the greys through the same runtime blend as before (rain and thunder without snow stay bit for bit as they were)
    vec3 rainGrey = vec3(mix(RAIN_SKY_GREY, SNOW_SKY_GREY, snow) / 255.0);
    vec3 stormGrey = vec3(mix(STORM_SKY_GREY, SNOW_SKY_GREY, snow) / 255.0);
    top = mix(mix(top, rainGrey, wet), stormGrey, thunderStrength * STORM_SKY_WEIGHT);
    rim = mix(mix(rim, rainGrey, wet), stormGrey, thunderStrength * STORM_SKY_WEIGHT);
    if (snow > 0.0) {
        // the pink horizon is the daylight's: it fades into the zenith's lavender while the sun goes down
        vec3 snowRim = mix(SNOW_SKY_TOP, SNOW_SKY_RIM, smoothstep(-0.1, 0.15, L.sun.dir.y)) / 255.0;
        top = mix(top, mix(clearTop, SNOW_SKY_TOP / 255.0, wet), snow);
        rim = mix(rim, mix(clearRim, snowRim, wet), snow);
    }
    L.skyTop = srgbToLinear(top);
    L.skyRim = srgbToLinear(rim);
    L.rayleigh = rayleigh;
    L.haloExponent = 1.0 / max(haloWidth, 1e-3);
    L.rimBase = -RIM_BELOW;
    L.rimSpan = rimHeight + RIM_BELOW;
    L.haloSpan = haloHeight;
    L.ambientFloor = vec3(AMBIENT_FLOOR);
    L.blockScale = BLOCK_LIGHT_INTENSITY;
    // the weather fog: while it rains or snows where the player is, the distance fog runs from 23 % to 70 %
    // of the render distance instead of 92 % to 100 % (its colour is the sky's, grey under the weather)
    vec2 fogRange = mix(FOG_RANGE, WEATHER_FOG_RANGE, wet * (biomeLookReady > 0.5 ? saturate(precipitationWeight) : 1.0));
    L.fogStart = fogRange.x;
    L.fogInvLength = 1.0 / (fogRange.y - fogRange.x);
    L.fogDistance = far;
    L.fogDensity = snow * wet * SNOW_FOG_DENSITY;
    L.caveFog = vec3(0.0);
    L.eyeSky = saturate(float(eyeBrightnessSmooth.y) / 240.0);

    #if defined DIM_NETHER
        L.sun = Celestial(L.sun.dir, vec3(1.0), OTHER_DIM_LUX, 0.0);
        L.moon = Celestial(L.moon.dir, vec3(1.0), OTHER_DIM_LUX, 0.0);
        L.keyLight = vec3(0.0);
        // the biome's atmosphere (shaders.properties): nether wastes and crimson forest red, warped forest purple, soul
        // sand valley teal, basalt deltas grey
        vec3 netherSky = biomeLookReady > 0.5 ? vec3(netherSkyR, netherSkyG, netherSkyB) : NETHER_SKY;
        L.skyTop = L.skyRim = srgbToLinear(netherSky / 255.0);
        L.rayleigh = biomeLookReady > 0.5 ? netherRayleigh : NETHER_RAYLEIGH;
        L.haloExponent = 1000.0;
        L.rimBase = -1.0; L.rimSpan = 1.800000011920929; L.haloSpan = 0.5;
        L.ambientFloor = vec3(NETHER_AMBIENT);
        L.fogStart = NETHER_FOG_BLOCKS.x;
        L.fogInvLength = 1.0 / (NETHER_FOG_BLOCKS.y - NETHER_FOG_BLOCKS.x);
        L.fogDistance = 1.0;
        L.eyeSky = 1.0;
    #elif defined DIM_END
        // No sun or moon in the End: the sky gradient is lit as by one above and one below (the sky
        // data), fixed, so it does not follow the (meaningless) celestial angle. The only direct light is the End
        // flash: Iris endFlashIntensity, from shadowLightPosition, which follows the flash with endFlashShadows
        // (shaders.properties). A constant white sun used to light the islands like an overworld noon.
        L.sun = Celestial(vec3(0.0, 1.0, 0.0), vec3(1.0), OTHER_DIM_LUX, 0.0);
        L.moon = Celestial(vec3(0.0, -1.0, 0.0), vec3(1.0), OTHER_DIM_LUX, 0.0);
        L.skyTop = srgbToLinear(END_SKY_TOP / 255.0);
        L.skyRim = srgbToLinear(END_SKY_RIM / 255.0);
        L.rayleigh = END_RAYLEIGH;
        L.haloExponent = 1000.0;
        L.rimBase = -0.25; L.rimSpan = 1.25; L.haloSpan = 0.5;
        L.ambientFloor = vec3(END_AMBIENT);
        // Iris gives a zero vector when there is no flash state
        L.keyDir = dot(shadowLightPosition, shadowLightPosition) > 1.0 ? normalize(mat3(gbufferModelViewInverse) * shadowLightPosition) : vec3(0.0, 1.0, 0.0);
        L.keyLight = srgbToLinear(END_FLASH_TINT / 255.0) * END_FLASH_LUX * saturate(endFlashIntensity);
        L.eyeSky = 1.0;
    #endif

#ifdef MOD_COMPAT
    if (mcCompatSkyless()) {
        L.sun.dir = vec3(0.0, 1.0, 0.0);
        L.moon.dir = vec3(0.0, -1.0, 0.0);
        L.sun.lux = 0.0; L.moon.lux = 0.0;
        L.sun.halo = 0.0; L.moon.halo = 0.0;
        L.keyDir = vec3(0.0, 1.0, 0.0);
        L.keyLight = vec3(0.0);
        L.fogDensity = 0.0;
        L.caveFog = mcCompatDimensionFog();
        L.ambientFloor = max(L.ambientFloor, vec3(0.035));
    }
#endif
    return L;
}

#endif
