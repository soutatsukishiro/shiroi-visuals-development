// Sky objects: sun, moon and stars, added into colortex5. The sky dome itself is computed per pixel in deferred, and
// colortex5 is added to the sky after the clouds have erased what is behind them (composite3).
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
out vec2 vUv;
out vec4 vColor;
out vec3 vDir;   // player space, towards the vertex
void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vColor = gl_Color;
    vDir = mat3(gbufferModelViewInverse) * (gl_ModelViewMatrix * gl_Vertex).xyz;
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
in vec3 vDir;
/* RENDERTARGETS: 5 */

// The moon texture holds the disc of the current phase in its central 8 x 8 texels of 32 (lit side and dark side),
// inside a faint square glow. Only the disc is kept: multiplied by the moon's light, that glow became a lit square
// around the moon (the moon has no halo of its own), and lifted the dark side of every phase until the moon looked
// full. The disc is found on the quad itself, which the game draws 20 units wide each side at 100 units, so it holds
// for a texture of any resolution: in the quad's plane the disc spans +-0.05 around the moon's direction.
float moonDisc(vec3 dir, vec3 moonDir) {
    vec3 across = vec3(0.0, 0.0, 1.0);               // the sky turns about world Z: one edge of the quad lies along it
    vec3 along = normalize(cross(moonDir, across));
    float d = dot(dir, moonDir);
    if (d <= 0.0) return 0.0;
    vec2 q = (vec2(dot(dir, along), dot(dir, across)) / d) / 0.4 * 32.0;   // texels from the quad's centre
    return all(lessThan(abs(q), vec2(4.0))) ? 1.0 : 0.0;
}
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
            float disc = moonDisc(normalize(vDir), L.moon.dir);
            radiance = srgbToLinear(tex.rgb) * tex.a * disc * L.moon.tint * max(L.moon.lux, MOON_MIN_LUX) * clearSky * SUN_DISC_INTENSITY;
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
