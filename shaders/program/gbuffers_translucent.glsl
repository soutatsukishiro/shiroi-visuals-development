// Translucent geometry.
//  water   only the surface description goes out here (normal, roughness, sky light -> colortex4; the vanilla texture
//          layer -> colortex1); composite lights it
//  others  stained glass, ice, slime, portals, translucent held items: lit right here into colortex0, alpha blended
#include "/lib/common.glsl"

#ifdef VERTEX_SHADER
in vec4 mc_Entity;
in vec4 mc_midTexCoord;
out vec2 vUv;
out vec2 vLm;
out vec4 vColor;
out vec3 vNormal;
out vec3 vPlayerPos;
flat out vec2 vMidUv;
flat out vec2 vHalfUv;
flat out int vMat;
#ifdef MOD_COMPAT
flat out int vCompatFallback;
#endif
#ifdef PBR_TABLE
#include "/lib/sprite_mean.glsl"
uniform sampler2D gtexture;
flat out vec2 vSpriteMean;   // the ice sprite's mean luminance / saturation (lib/surface.glsl texelDetailMaterial)
#endif

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLm = normalizeLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    vColor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPos = (gbufferModelViewInverse * viewPos).xyz;
    vNormal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    vMidUv = mc_midTexCoord.xy;
    vHalfUv = abs(vUv - mc_midTexCoord.xy);
    #ifdef GBUF_HAND_WATER
        vMat = MAT_HAND;
    #else
        vMat = int(mc_Entity.x + 0.5);
    #endif

#ifdef MOD_COMPAT
    vCompatFallback = 0;
    #ifndef GBUF_HAND_WATER
        vCompatFallback = (vMat <= MAT_DEFAULT || vMat > MAT_LAST_BLOCK) ? 1 : 0;
        if (vMat < MAT_DEFAULT || vMat > MAT_LAST_BLOCK) vMat = MAT_DEFAULT;
    #endif
    if (vCompatFallback != 0) {
        vLm = mcCompatLightmap(vLm);
        if (!mcCompatNormalOK(vNormal)) vNormal = vec3(0.0);
        // Missing midpoint data must not be interpreted as an atlas sprite.
        if (any(isnan(vMidUv)) || any(isinf(vMidUv)) || any(lessThanEqual(vMidUv, vec2(0.0))) ||
            any(greaterThan(vMidUv, vec2(1.0))) || any(isnan(vHalfUv)) || any(isinf(vHalfUv))) {
            vHalfUv = vec2(0.0);
        }
    }
#endif
    #ifdef PBR_TABLE
        // the same for every fragment of the face, so it is read here, once per corner. In the fragment stage its 16
        // reads next to the shadow transmission loops of the ice's subsurface light pushed the shader past the GPU's
        // registers: over a frozen lake this pass took 40 ms a frame instead of 1.5 (RTX 3050, 1080p)
        vSpriteMean = vMat == MAT_ICE && vHalfUv.x > 0.0 && vHalfUv.y > 0.0 ? spriteMeanLumSat(gtexture, vMidUv, vHalfUv) : vec2(0.5, 0.0);
    #endif
    gl_Position = taaJitterClip(gl_ProjectionMatrix * viewPos);
}
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/gbuffer.glsl"
#include "/lib/surface.glsl"
#include "/lib/shading.glsl"
uniform sampler2D gtexture;
#ifdef GBUF_HAND_WATER
uniform int currentRenderedItemId;   // the held item (item.properties)
#endif
uniform sampler2D specular;           // Iris PBR atlases (the texture sets of the resource pack)
uniform sampler2D normals;
// water texture set (customTexture): normal maps and MERS of the still (16 x 512) and flowing (normal 32 x 1024,
// MERS 16 x 512) water, 32 animation frames stacked vertically
uniform sampler2D waterNormalStill;
uniform sampler2D waterNormalFlow;
uniform sampler2D waterMersStill;
uniform sampler2D waterMersFlow;
in vec2 vUv;
in vec2 vLm;
in vec4 vColor;
in vec3 vNormal;
in vec3 vPlayerPos;
flat in vec2 vMidUv;
flat in vec2 vHalfUv;
flat in int vMat;
#ifdef MOD_COMPAT
flat in int vCompatFallback;
#endif
#ifdef PBR_TABLE
flat in vec2 vSpriteMean;
#endif


/* RENDERTARGETS: 0,4,1,5,2 */
layout(location = 0) out vec4 outColor;
// colortex4: the water surface (normal, roughness | sky light, alpha 1). Blended with its alpha (shaders.properties):
// other translucents write alpha 0 and leave the water under them, which they used to erase (ice hid the lake)
layout(location = 1) out vec4 outWater;
// colortex1 (free after deferred). With WATER_TEXTURE: the water texture layer (written without blending). Without it:
// the premultiplied colour of the translucents in front of the nearest water, blended ONE / ONE_MINUS_SRC_ALPHA (water
// writes alpha 1 and clears it); composite takes it out, puts the water under it and the translucents back on top
layout(location = 2) out vec4 outWaterTex;
layout(location = 3) out vec4 outSkyObjects; // alpha blended: glass in front of the sun dims it (added in composite)
// colortex2.b (free after deferred, whose glow is in .r): what the translucents in front of the nearest water surface
// let through. Blend ONE / ONE_MINUS_SRC_ALPHA: water writes 1 with alpha 0 (resets it, the result is clamped to 1),
// every other translucent writes 0 with its alpha (multiplies by 1 - alpha); composite shows the water through it.
// colortex2.g (0 after deferred): the coverage of all of them, the water leaves it as it is. (1 - g) / b is then what
// the ones drawn before the water let through: the submerged part of an ice side face, which the game sorts before the
// water quad of a hole, is under the surface and not lake floor
layout(location = 4) out vec4 outCover;

#ifdef WATER_TEXTURE_NORMALS
// Normal and roughness of the water texture set at this fragment.
// Sprite layout of Java's liquid renderer: k atlas pixels per block (16 in vanilla, measured here from the screen
// derivatives of uv against position). The still sprite (k px) covers a whole top / bottom face; the flowing sprite
// (2k px) covers side faces and flowing tops, rotated about its centre. On top faces mc_midTexCoord is that centre:
// half a k px step off the grid for the still sprite, on the grid for the flowing one.
void waterTextureSet(vec3 N, inout vec3 Nw, inout float roughness) {
    vec2 atlas = vec2(textureSize(gtexture, 0));
    vec2 uvPx = vUv * atlas, midPx = vMidUv * atlas;
    vec2 dux = dFdx(uvPx), duy = dFdy(uvPx);
    vec3 dpx = dFdx(vPlayerPos), dpy = dFdy(vPlayerPos);
    float texelsPerBlock = exp2(round(0.5 * log2((dot(dux, dux) + dot(duy, duy)) / max(dot(dpx, dpx) + dot(dpy, dpy), 1e-12))));
    bool flowing = abs(N.y) < 0.5 || abs(fract(midPx.x / texelsPerBlock) - 0.5) > 0.25;
    float spritePx = flowing ? 2.0 * texelsPerBlock : texelsPerBlock;
    vec2 local = clamp((uvPx - floor(midPx / spritePx) * spritePx) / spritePx, 0.0, 0.99999);

    // animation of the colour texture: a frame per tick when flowing, per two ticks when still; frames blended
    float frame = frameTimeCounter * 20.0 / (flowing ? 1.0 : 2.0);
    int f0 = int(mod(floor(frame), 32.0)), f1 = (f0 + 1) % 32;
    float blend = fract(frame);
    int normalRes = flowing ? 32 : 16;
    ivec2 tn = ivec2(local * float(normalRes)), tm = ivec2(local * 16.0);
    vec3 encoded;
    vec2 rough;   // MERS blue = roughness, of both frames
    if (flowing) {
        encoded = mix(texelFetch(waterNormalFlow, tn + ivec2(0, f0 * 32), 0).rgb, texelFetch(waterNormalFlow, tn + ivec2(0, f1 * 32), 0).rgb, blend);
        rough = vec2(texelFetch(waterMersFlow, tm + ivec2(0, f0 * 16), 0).b, texelFetch(waterMersFlow, tm + ivec2(0, f1 * 16), 0).b);
    } else {
        encoded = mix(texelFetch(waterNormalStill, tn + ivec2(0, f0 * 16), 0).rgb, texelFetch(waterNormalStill, tn + ivec2(0, f1 * 16), 0).rgb, blend);
        rough = vec2(texelFetch(waterMersStill, tm + ivec2(0, f0 * 16), 0).b, texelFetch(waterMersStill, tm + ivec2(0, f1 * 16), 0).b);
    }
    roughness = mix(rough.x, rough.y, blend);

    // tangent-space normal as a slope (dh/du, dh/dv), faded out while the map is minified from 1 to 2 texels per
    // pixel (lod 0..1) so distant water does not sparkle, then rebuilt around N
    vec3 n = encoded * 2.0 - 1.0;
    vec2 slope = n.xy / max(n.z, 1e-3);
    vec2 p = local * float(normalRes);
    float lod = max(0.5 * log2(max(dot(dFdx(p), dFdx(p)), dot(dFdy(p), dFdy(p)))), 0.0);
    slope *= 1.0 - min(lod * lod, 1.0);
    // the tangent frame belongs to the vertex normal: on back faces only N itself is flipped
    mat3 tbn = derivativeFrame(gl_FrontFacing ? N : -N, vPlayerPos, vUv);
    Nw = normalize(tbn[0] * slope.x + tbn[1] * slope.y + N);
}
#endif

#ifdef WATER_WAVES
// Iterated directional waves: each octave is a sine with sharpened crests, turned, finer, faster and weaker than the
// last, and shifts the position the following octaves see along its own direction (domain warp). The normal comes
// from the analytic slope of the sum, normalised by the total amplitude.
vec3 waveNormal(vec2 p, float t) {
    float freq = 1.0, amp = 1.0, speed = WAVE_SPEED, angle = 0.0, ampSum = 0.0;
    vec2 slope = vec2(0.0);
    for (int i = 0; i < WAVE_OCTAVES; i++) {
        vec2 dir = vec2(sin(angle), cos(angle));
        float phase = dot(dir, p) * freq + t * speed;
        float s = sin(phase), c = cos(phase);
        float h = pow((s + 1.0) * 0.5, WAVE_SHARPNESS);     // crest profile, 0..1
        float dh = WAVE_SHARPNESS * c * h / (s + 1.0001);    // dh / dphase
        slope -= dir * (freq * amp * dh);
        p -= dir * (h * amp * c * WAVE_DRAG);
        ampSum += amp;
        amp *= WAVE_OCTAVE_STEP.x; freq *= WAVE_OCTAVE_STEP.y; speed *= WAVE_OCTAVE_STEP.z; angle += WAVE_OCTAVE_STEP.w;
    }
    return normalize(vec3(slope.x / ampSum, 1.0, slope.y / ampSum));
}
#endif

void main() {
    sceneGuard();

#ifdef MOD_COMPAT
    vec3 compatFace = mcCompatFaceNormal(vPlayerPos);
#endif
    vec4 tex = texture(gtexture, vUv);
    #if defined GBUF_ENTITIES || defined GBUF_HAND || defined GBUF_HAND_WATER
        // Glow resource packs (Enchantment Glows and others using the same convention) mark texels by their alpha:
        // 252 emissive, 253 emissive with shading, 250 / 251 opaque with less or no shading. Vanilla's own shaders
        // read the marks; under Iris they reach this program, so the glow is made here: 252 / 253 glow as emissive
        // texels (and bloom), and every marked texel is made opaque again
        int alphaMark = int(tex.a * 255.0 + 0.5);
        float markedGlow = alphaMark == 252 ? 1.0 : (alphaMark == 253 ? GLOW_MARK_SHADED : 0.0);
        if (alphaMark >= 250 && alphaMark <= 253) tex.a = 1.0;
    #endif
    vec3 N = gl_FrontFacing ? normalize(vNormal) : -normalize(vNormal);
#ifdef MOD_COMPAT
    if (vCompatFallback != 0 && !mcCompatNormalOK(N)) N = compatFace;
#endif


    if (vMat == MAT_WATER) {
        vec3 Nw = N;
        float roughness = 0.04;   // without the texture set
        #ifdef WATER_TEXTURE_NORMALS
            if (vHalfUv.x > 0.0 && vHalfUv.y > 0.0) waterTextureSet(N, Nw, roughness);
        #endif
        #ifdef WATER_WAVES
            Nw = normalize(mix(Nw, waveNormal(vPlayerPos.xz + cameraPosition.xz, frameTimeCounter * WAVE_TIME_SCALE), N.y));
        #endif
        outColor = vec4(0.0);
        outWater = vec4(octEncode(Nw) * 0.5 + 0.5, pack2x8(vec2(roughness, vLm.y)), 1.0);
        #ifdef WATER_TEXTURE
            // the vanilla texture tinted with the biome water colour (vertex colour), with its own alpha
            outWaterTex = vec4(tex.rgb * vColor.rgb, tex.a);
        #else
            outWaterTex = vec4(0.0, 0.0, 0.0, 1.0);
        #endif
        outSkyObjects = vec4(0.0);   // composite lights the water surface itself, over the sun
        outCover = vec4(0.0, 0.0, 1.0, 0.0);
        return;
    }

    vec4 c = tex * vColor;
    if (c.a < 0.004) discard;
    Material m = blockMaterial(vMat == MAT_HAND ? MAT_GLASS : vMat, tex.rgb);
    #ifdef GBUF_HAND_WATER
        // Flat items (a torch or a lantern in the hand is a sprite) are drawn translucent, so they come here and not
        // to gbuffers_hand: the flame glows as the placed block's does, with its material instead of the glass one.
        // For an item that places a block Iris gives the block's id (block.properties), not an item id
        if (currentRenderedItemId == MAT_EMISSIVE_TORCH || currentRenderedItemId == MAT_EMISSIVE_FULL)
            m = blockMaterial(currentRenderedItemId, tex.rgb);
        m.emissive = max(m.emissive, markedGlow);
    #endif
    // ice (and frosted ice) texel by texel, as the solid ices in gbuffers_solid (lib/surface.glsl texelDetailMaterial)
    #ifdef PBR_TABLE
        if (vMat == MAT_ICE && vHalfUv.x > 0.0 && vHalfUv.y > 0.0) texelDetailMaterial(m, vMat, tex.rgb, vSpriteMean);
    #endif
    vec3 tsNormal = vec3(0.0, 0.0, 1.0);
    bool normalMapped = vMat != MAT_HAND && textureSetMaterial(specular, normals, vUv, m, tsNormal) && tsNormal.z < 0.9999;
    vec3 geoNormal = N;
    if (normalMapped) N = normalize(derivativeFrame(geoNormal, vPlayerPos, vUv) * tsNormal);
    #ifdef MICRO_DETAIL
        else if (vMat != MAT_HAND && vMat != MAT_NETHER_PORTAL && vHalfUv.x > 0.0 && vHalfUv.y > 0.0)
            N = normalize(derivativeFrame(geoNormal, vPlayerPos, vUv) * texelRelief(gtexture, vUv, vMidUv, vHalfUv));
    #endif


#ifdef MOD_COMPAT
    if (vCompatFallback != 0) {
        if (!mcCompatNormalOK(N)) N = geoNormal;
        if (any(isnan(c)) || any(isinf(c))) c = vec4(mcCompatColor(c.rgb), mcCompatFinite(c.a) ? clamp(c.a, 0.0, 1.0) : 1.0);
        if (!mcCompatFinite(m.metal) || !mcCompatFinite(m.emissive) ||
            !mcCompatFinite(m.roughness) || !mcCompatFinite(m.sss)) m = defaultMaterial();
    }
#endif
    Surface s;
    s.albedo = srgbToLinear(c.rgb);
    s.metal = m.metal;
    s.sss = m.sss;
    s.roughness = m.roughness;
    s.emissive = m.emissive;
    s.blockLevel = vLm.x;
    s.skyLevel = vLm.y;
    s.normal = N;
    s.pos = vPlayerPos;
    s.flatNormal = geoNormal;
    s.viewDepth = -(gbufferModelView * vec4(vPlayerPos, 1.0)).z;
    float dist = length(vPlayerPos);
    vec3 V = vPlayerPos / max(dist, 1e-4);
    float caustics = submergedCaustics(vPlayerPos + cameraPosition, N);
    float fogT;
    KeyLightResult key;
    vec3 col = shadeSurface(s, daylight(), V, dist, skyIrradianceNow(), vec4(0.0), caustics, fogT, key);
    outColor = vec4(sanitize(col), c.a);
    outWater = vec4(0.0);
    #ifdef WATER_TEXTURE
        outWaterTex = vec4(0.0);
    #else
        outWaterTex = vec4(sanitize(col) * c.a, c.a);
    #endif
    outSkyObjects = vec4(0.0, 0.0, 0.0, c.a);
    outCover = vec4(0.0, c.a, 0.0, c.a);
}
#endif
