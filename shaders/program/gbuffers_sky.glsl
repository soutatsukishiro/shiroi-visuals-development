// Sky objects: sun, moon and stars, added into colortex5. The sky dome itself is computed per pixel in deferred, and
// colortex5 is added to the sky after the clouds have erased what is behind them (composite3).
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
out vec2 vUv;
out vec4 vColor;
void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    #ifdef TAA
        gl_Position = taaJitterClip(ftransform());
    #else
        gl_Position = sceneClip(ftransform());
    #endif
}
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/daylight.glsl"
uniform sampler2D gtexture;
uniform int renderStage;
in vec2 vUv;
in vec4 vColor;
/* RENDERTARGETS: 5 */
layout(location = 0) out vec4 outSky;
void main() {
    sceneGuard();

#ifdef MOD_COMPAT
    if (mcCompatSkyless()) discard;
#endif
    Daylight L = daylight();
    #ifdef SKY_TEXTURED
        vec4 tex = texture(gtexture, vUv);
        vec3 radiance;
        float clearSky = 1.0 - rainStrength;   // rain hides the discs, as in vanilla
        if (renderStage == MC_RENDER_STAGE_MOON) {
            radiance = srgbToLinear(tex.rgb) * tex.a * L.moon.tint * max(L.moon.lux, MOON_MIN_LUX) * clearSky * SUN_DISC_INTENSITY;
        } else if (renderStage == MC_RENDER_STAGE_SUN) {
            // only the bright disc of the texture: its faint outer glow, multiplied by the sun's illuminance, would
            // turn into a grid of texels; the glow around the sun comes from the sky halo instead
            float disc = step(0.5, max(tex.r, max(tex.g, tex.b)));
            radiance = srgbToLinear(tex.rgb) * disc * L.sun.tint * L.sun.lux * clearSky * SUN_DISC_INTENSITY;
        } else {
            radiance = srgbToLinear(tex.rgb) * vColor.rgb * vColor.a;
        }
        outSky = vec4(radiance, 1.0);
    #else
        if (renderStage != MC_RENDER_STAGE_STARS) discard;
        outSky = vec4(vec3(STAR_BRIGHTNESS) * STAR_INTENSITY * vColor.rgb * vColor.a, 1.0);
    #endif
}
#endif
