// Forward programs, mostly drawn after deferred.
//  FWD_PARTICLES  particles: ambient + key light with cascade shadows, full-bright particles emissive
//  FWD_WEATHER    rain and snow, lit the same way
//  FWD_BASIC      lines and outlines
//  FWD_EMISSIVE   beacon beam and eye layers (full emissive)
//  FWD_GLINT      enchantment glint (additive overlay into colortex7, added by deferred / composite)
//  FWD_DAMAGE     block breaking cracks (multiplied into the albedo buffer)
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
out vec2 vUv;
out vec2 vLm;
out vec4 vColor;
out vec3 vPlayerPos;
void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLm = normalizeLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    vColor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPos = (gbufferModelViewInverse * viewPos).xyz;
    #ifdef FWD_LINE
        // MC 26 sends each segment of a line as two triangles whose four corners all sit on the segment's ends (every
        // vertex written twice, the segment direction as its normal); the vertex shader opens them to the line width,
        // one side or the other by gl_VertexID parity, as vanilla's own line shader does. Iris does that only for its
        // own programs, not for a pack's gbuffers_line: drawn as they came, the triangles had no area and the block
        // outline never showed. Pulled 1/256 towards the camera (vanilla's VIEW_SCALE) so it stays over the faces it
        // borders, ~2.5 px wide at 1080p, and on the pixel grid (TAA keeps no history under it, so a jittered line
        // would shimmer).
        const float VIEW_SHRINK = 1.0 - 1.0 / 256.0;
        vec4 lineStart = gl_ProjectionMatrix * vec4(viewPos.xyz * VIEW_SHRINK, 1.0);
        vec4 lineEnd = gl_ProjectionMatrix * vec4((gl_ModelViewMatrix * vec4(gl_Vertex.xyz + gl_Normal, 1.0)).xyz * VIEW_SHRINK, 1.0);
        vec2 size = sceneSize();
        vec3 ndcStart = lineStart.xyz / lineStart.w;
        vec2 screenDir = (lineEnd.xy / lineEnd.w - ndcStart.xy) * size;
        screenDir = dot(screenDir, screenDir) > 1e-12 ? normalize(screenDir) : vec2(1.0, 0.0);
        vec2 lineOffset = vec2(-screenDir.y, screenDir.x) * max(2.0, size.y / 1080.0 * 2.5) / size;
        if (lineOffset.x < 0.0) lineOffset = -lineOffset;
        if (gl_VertexID % 2 != 0) lineOffset = -lineOffset;
        gl_Position = sceneClip(vec4((ndcStart + vec3(lineOffset, 0.0)) * lineStart.w, lineStart.w));
    #else
        gl_Position = taaJitterClip(gl_ProjectionMatrix * viewPos);
    #endif
}
#endif

#ifdef FRAGMENT_SHADER
uniform sampler2D gtexture;
in vec2 vUv;
in vec2 vLm;
in vec4 vColor;
in vec3 vPlayerPos;

#if defined FWD_PARTICLES || defined FWD_WEATHER
#include "/lib/shading.glsl"
// Particles and weather come after the translucent terrain (particles.ordering = AFTER), so depthtex1 holds none of
// them and composite treated them as sky: fog volume and sun over them (falling leaves looked orange and see-through,
// as the player did). They leave -(2 + view depth) in colortex7.a (rgb kept: blend ZERO ONE ONE ZERO) and their
// coverage in colortex5.a (alpha blended, which also dims the sun / moon behind them); composite3 blends the volume
// at their depth with the one behind by that coverage.
// FWD_PARTICLES_SOLID (gbuffers_particles, Iris 1.11): MC 26 draws the opaque particles (falling leaves, block crumbs)
// in the solid feature phase, before Iris' deferred, and Iris 1.11 no longer applies particles.ordering. Deferred then
// relit those pixels as the block behind them: transparent particles. colortex3.w = 0.5 (forward) makes it keep their
// colour; drawn after deferred (older Iris honouring the ordering) the flag only gives composite their depth.
// outputs are declared and first written in location order (Vitrail numbers them by first write)
layout(location = 0) out vec4 outColor;
#ifdef FWD_PARTICLES_SOLID
/* RENDERTARGETS: 0,2,7,5,3 */
layout(location = 1) out vec4 outGlow;
layout(location = 2) out vec4 outLateDepth;
layout(location = 3) out vec4 outCoverage;
layout(location = 4) out vec4 outFlag;    // colortex3, blend off (shaders.properties)
#elif defined FWD_PARTICLES
/* RENDERTARGETS: 0,2,7,5 */
layout(location = 1) out vec4 outGlow;   // added (ONE ONE) to the glow weight read by the bloom
layout(location = 2) out vec4 outLateDepth;
layout(location = 3) out vec4 outCoverage;
#else
/* RENDERTARGETS: 0,7,5 */
layout(location = 1) out vec4 outLateDepth;
layout(location = 2) out vec4 outCoverage;
#endif
void main() {
    sceneGuard();
    vec4 c = texture(gtexture, vUv) * vColor;
    #ifdef FWD_PARTICLES_SOLID
        if (c.a < 0.1) discard;   // vanilla's cutout for opaque particles (drawn without blending)
    #else
        if (c.a < 0.004) discard;
    #endif
    float dist = length(vPlayerPos);
    vec3 V = vPlayerPos / max(dist, 1e-4);
    // a camera-facing card: rough, not metallic, normal towards the camera
    Surface s;
    s.albedo = srgbToLinear(c.rgb);
    s.metal = 0.0;
    s.sss = 0.0;
    s.roughness = 1.0;
    s.emissive = 0.0;
    #ifdef FWD_PARTICLES
        s.emissive = step(0.99, vLm.x);   // full-bright lightmap: a glowing particle (flame, spark, glow squid ink)
    #endif
    s.blockLevel = vLm.x;
    s.skyLevel = vLm.y;
    s.normal = -V;
    s.flatNormal = -V;
    s.pos = vPlayerPos;
    s.viewDepth = -(gbufferModelView * vec4(vPlayerPos, 1.0)).z;
    float fogT;
    KeyLightResult key;
    vec3 col = shadeSurface(s, daylight(), V, dist, skyIrradianceNow(), vec4(0.0), 1.0, fogT, key);
    outColor = vec4(sanitize(col), c.a);
    #ifdef FWD_PARTICLES
        outGlow = vec4(s.emissive * c.a / GLOW_WEIGHT_RANGE, 0.0, 0.0, 0.0);
    #endif
    outLateDepth = vec4(0.0, 0.0, 0.0, -(2.0 + s.viewDepth));
    outCoverage = vec4(0.0, 0.0, 0.0, c.a);
    #ifdef FWD_PARTICLES_SOLID
        outFlag = vec4(vLm, float(MAT_PARTICLE) / 255.0, 0.5);
    #endif
}
#endif

// lines, beams and eyes can be drawn before deferred: colortex3.w = 0.5 makes deferred keep this colour
// (colortex3 blending is off for these programs in shaders.properties)
#ifdef FWD_BASIC
/* RENDERTARGETS: 0,3 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outFlag;
void main() {
    sceneGuard();
    vec4 c = vColor;
    if (c.a < 0.004) discard;
    #ifdef FWD_LINE
        // MC 26 draws the block outline after deferred (executeTranslucent, shapeOutlines phase), over the lit scene.
        // Vanilla blends it over display colours: black at alpha 0.4 leaves 0.6 of the display value, which is
        // 0.6^2.2 of the linear one. Same look here; MAT_OUTLINE keeps TAA from blurring the thin line away.
        outColor = vec4(srgbToLinear(c.rgb), 1.0 - pow(1.0 - c.a, 2.2));
        #if DEBUG_VIEW == 8
            outColor = vec4(20.0, 0.0, 20.0, 1.0);   // outline diagnosis: opaque bright magenta
        #endif
        outFlag = vec4(0.0, 0.0, float(MAT_OUTLINE) / 255.0, 0.5);
    #else
        outColor = vec4(srgbToLinear(c.rgb) * 2.0, c.a);
        outFlag = vec4(0.0, 0.0, 0.0, 0.5);
    #endif
}
#endif

#ifdef FWD_EMISSIVE
// eye layers (spider, cave spider, enderman, phantom, ender dragon) and beacon beams: full emissive, marked MAT_EYES
// in colortex3 and glowing in colortex2 (the bloom reads it after deferred)
/* RENDERTARGETS: 0,3,2 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outFlag;
layout(location = 2) out vec4 outGlow;
void main() {
    sceneGuard();
    vec4 c = texture(gtexture, vUv) * vColor;
    if (c.a < 0.004) discard;
    outColor = vec4(srgbToLinear(c.rgb) * 4.0 * EMISSIVE_STRENGTH, c.a);
    outFlag = vec4(0.0, 0.0, float(MAT_EYES) / 255.0, 0.5);
    outGlow = vec4(c.a / GLOW_WEIGHT_RANGE, 0.0, 0.0, 1.0);
}
#endif

#ifdef FWD_GLINT
#include "/lib/exposure.glsl"
/* RENDERTARGETS: 7 */
layout(location = 0) out vec4 outColor;
void main() {
    sceneGuard();
    vec4 c = texture(gtexture, vUv) * vColor;
    // Vanilla adds the glint on screen, so it shows the same by day and by night. Here it is light added to the HDR
    // scene: a fixed amount was lost against the sun (some 100 lux) and only showed at night. It is scaled to the
    // brightness the exposure brings to the screen instead (program/final.glsl), and glows (deferred adds it to the
    // bloom). The texture scrolls (vanilla's texture matrix): the shine moves over the item.
    outColor = vec4(glintRadiance(c.rgb) * c.a, c.a);
}
#endif

#ifdef FWD_DAMAGE
// Blend DST_COLOR / SRC_COLOR: 2 x crack x destination, as vanilla (grey 128 leaves it, darker cracks, lighter rims).
// MC 26 draws it after deferred (breakingOverlay phase), so it multiplies the lit colour: in linear the vanilla factor
// 2s on display colours is (2s)^2.2. Older versions draw it before deferred: the albedo (sRGB) gets 2s itself.
// The clear texels of destroy_stage_* are white with alpha 1/255: vanilla discards below 0.1, without that the whole
// block doubled in brightness.
/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outAlbedo;
void main() {
    sceneGuard();
    vec4 c = texture(gtexture, vUv) * vColor;
    if (c.a < 0.1) discard;
    outColor = vec4(0.5 * pow(2.0 * c.rgb, vec3(2.2)), c.a);
    outAlbedo = c;
}
#endif
#endif
