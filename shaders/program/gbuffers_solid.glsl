// Opaque geometry: terrain, block entities, entities and the held item write the G-buffer (layout in
// lib/gbuffer.glsl). Terrain is lit later by deferred; the others are also lit here, see GBUF_FORWARD.
#include "/lib/common.glsl"
#include "/lib/gbuffer.glsl"
#ifdef GBUF_ENTITIES
    #include "/lib/entitymotion.glsl"
#endif
#if defined GBUF_TERRAIN && defined COLORED_LIGHT && defined VERTEX_SHADER
    #define LC_SPLAT
    #include "/lib/lightcolor.glsl"
    uniform sampler2D gtexture;
#endif

#ifdef VERTEX_SHADER
in vec4 mc_Entity;
in vec4 mc_midTexCoord;
uniform int blockEntityId;
uniform int entityId;
out vec2 vUv;
out vec2 vLm;
out vec4 vColor;
out vec3 vNormal;
out vec3 vPlayerPos;
flat out vec2 vMidUv;
flat out vec2 vHalfUv;
flat out int vMat;
#ifdef GBUF_ENTITIES
flat out int vNameTagAlpha;
#endif
#if defined GBUF_ENTITIES && defined ENTITY_MOTION
out vec4 vPrevPos;   // camera-relative position in the previous frame, w 1 when tracked (lib/entitymotion.glsl)
#endif
#ifdef MOD_COMPAT
flat out int vCompatFallback;
#endif

void main() {
    vUv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vLm = normalizeLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
    vColor = gl_Color;
    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vPlayerPos = (gbufferModelViewInverse * viewPos).xyz;
    vNormal = normalize(mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal));
    vMidUv = mc_midTexCoord.xy;
    vHalfUv = abs(vUv - mc_midTexCoord.xy);   // half size of the sprite in the atlas
    #if defined GBUF_TERRAIN
        vMat = int(mc_Entity.x + 0.5);
        #ifdef COLORED_LIGHT
            // light sources (one corner per quad) give their colour to the light grid (lib/lightcolor.glsl); the
            // Nether has no shadow pass, which does it elsewhere
            if ((vMat == MAT_EMISSIVE_FULL || vMat == MAT_EMISSIVE_TORCH || vMat == MAT_LAVA) && (gl_VertexID & 3) == 0)
                lightSplat(gtexture, vUv, mc_midTexCoord.xy, vPlayerPos);
        #endif
    #elif defined GBUF_BLOCK
        vMat = blockEntityId;
    #elif defined GBUF_HAND
        vMat = MAT_HAND;
    #else
        // the End portal and gateway are block entities that Iris draws as a plain entity (see endPortalStars)
        vMat = blockEntityId == MAT_NETHER_PORTAL ? MAT_NETHER_PORTAL : MAT_ENTITY;
    #endif

#ifdef MOD_COMPAT
    vCompatFallback = 0;
    #if defined GBUF_TERRAIN || defined GBUF_BLOCK
        bool knownId = vMat >= MAT_DEFAULT && (vMat <= MAT_LAST_BLOCK || vMat == MAT_END_FRAME_EYE);
        vCompatFallback = (!knownId || vMat == MAT_DEFAULT) ? 1 : 0;
        if (!knownId) vMat = MAT_DEFAULT;
    #elif defined GBUF_ENTITIES
        // entity.30 is assigned only to confirmed mod registry names.
        vCompatFallback = entityId == MAT_ENTITY ? 2 : 1;
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
    #ifdef GBUF_ENTITIES
        // Iris labels vanilla name tags explicitly. Cobblemon overrides the vanilla
        // method: its SEE_THROUGH text instead carries alpha 0x20 and full light,
        // and its translucent background is black. Both are camera-facing cards.
        vec3 nameViewNormal = mat3(gbufferModelView) * vNormal;
        bool nameCard = abs(nameViewNormal.z) > 0.999 &&
                        max(abs(nameViewNormal.x), abs(nameViewNormal.y)) < 0.02;
        bool labelLayer = abs(vColor.a - (32.0 / 255.0)) < (0.5 / 255.0) ||
                          max(abs(vColor.r), max(abs(vColor.g), abs(vColor.b))) < 0.0001;
        // Text-background draws may have no normal/UV attributes at all.
        bool plainBackground = max(abs(vColor.r), max(abs(vColor.g), abs(vColor.b))) < 0.0001 &&
                               max(vHalfUv.x, vHalfUv.y) < 0.0000001;
        bool customLabel = min(vLm.x, vLm.y) > 0.999 && vColor.a < 0.999 &&
                           ((nameCard && labelLayer) || plainBackground);
        vNameTagAlpha = (entityId == 10001 || customLabel) ? 1 : 0;
        #ifdef ENTITY_MOTION
            vPrevPos = vNameTagAlpha != 0 ? vec4(0.0) : trackEntityVertex(entityId, vUv, vPlayerPos);
        #endif
    #endif
    gl_Position = taaJitterClip(gl_ProjectionMatrix * viewPos);
}
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/surface.glsl"
#ifndef GBUF_TERRAIN
    // MC 26 batches entity drawing and Iris does not promise it happens before deferred; what is drawn after it would
    // never be lit from the G-buffer (players and mobs went missing). So these are lit right here and flagged
    // SURFACE_FORWARD, and deferred keeps their colour in either order.
    #define GBUF_FORWARD
    #include "/lib/shading.glsl"
#endif
uniform sampler2D gtexture;
uniform sampler2D specular;   // Iris PBR atlases (the texture sets of the resource pack)
uniform sampler2D normals;
uniform vec4 entityColor;
uniform float alphaTestRef;
#if defined GBUF_ENTITIES || defined GBUF_HAND
uniform int currentRenderedItemId;   // the item drawn now, armour layers included (item.properties)
#endif
#ifdef GBUF_FORWARD
#include "/lib/exposure.glsl"
#ifdef IRIS_INLINE_GLINT
// the glint of an item drawn with it (lib/exposure.glsl glintRadiance): Iris fills these in
bool mc_hasGlint();
vec3 mc_sampleGlint();
#endif
#endif
in vec2 vUv;
in vec2 vLm;
in vec4 vColor;
in vec3 vNormal;
in vec3 vPlayerPos;
flat in vec2 vMidUv;
flat in vec2 vHalfUv;
flat in int vMat;
#ifdef GBUF_ENTITIES
flat in int vNameTagAlpha;
#endif
#if defined GBUF_ENTITIES && defined ENTITY_MOTION
in vec4 vPrevPos;
#endif
#ifdef MOD_COMPAT
flat in int vCompatFallback;
#endif


// outputs are declared and first written in location order (Vitrail numbers them by first write)
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outLight;
#ifdef GBUF_FORWARD
#if defined GBUF_ENTITIES && defined ENTITY_MOTION
/* RENDERTARGETS: 1,2,3,0,7,5,4 */
#else
/* RENDERTARGETS: 1,2,3,0,7,5 */
#endif
layout(location = 3) out vec4 outColor;
// colortex7: rgb 0 (glint drawn afterwards adds to it), a = 2 + view depth. MC 26 draws translucent entity parts
// (player skins are entityTranslucent) after the deferred pass and after Iris copies depthtex1, so composite had no
// depth for them: against the sky they took the whole fog volume, under water the extinction down to the floor.
// Deferred overwrites colortex7 everywhere, so this depth survives only for what is drawn after it.
layout(location = 4) out vec4 outLateDepth;
// colortex5: the entity's direct light (what deferred writes to colortex7 for the G-buffer); composite3 moves it to
// colortex7 for the caustics under water. An entity pixel never shows the sun or moon that colortex5 otherwise holds.
layout(location = 5) out vec4 outDirect;
#if defined GBUF_ENTITIES && defined ENTITY_MOTION
// colortex4 (the water buffer, empty where an entity is in front: water drawn later fails the depth test there): the
// entity's screen motion for the TAA, written through the depth test so the visible surface wins, deterministically
// (lib/entitymotion.glsl). r, g: motion (uv) x 2 + 0.5, b: previous view depth / 512 (0: no vector), a: 0 (no water)
layout(location = 6) out vec4 outMotion;
#endif
#else
/* RENDERTARGETS: 1,2,3 */
#endif

#if defined GBUF_BLOCK || defined GBUF_ENTITIES
// The End portal and gateway (block.properties 19, as block entities). With a shader pack Iris replaces vanilla's
// layered starfield by one layer of its texture (sparse white stars on black), darkened to a deep teal: an almost black
// block. Drawn here instead as a field of stars in depth: END_PORTAL_LAYERS layers of stars made in the shader, each at its own
// depth behind the face (so they slide over each other as the view turns), turned, scaled and drifting slowly, in
// teal, green and blue, over a dark teal ground; all of it emissive.
vec3 endPortalStars(vec3 playerPos, vec3 n) {
    vec3 V = normalize(playerPos);
    vec3 t = abs(n.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : normalize(vec3(-n.z, 0.0, n.x));
    vec3 b = cross(n, t);
    vec3 world = playerPos + cameraPosition;
    vec2 face = vec2(dot(world, t), dot(world, b));
    vec2 slope = vec2(dot(V, t), dot(V, b)) / max(abs(dot(V, n)), 0.2);   // across the face per block of depth
    vec3 stars = END_PORTAL_GROUND;
    for (int i = 0; i < END_PORTAL_LAYERS; i++) {
        float k = float(i);
        float angle = k * 2.39996;   // the golden angle: no two layers line up
        mat2 turn = mat2(cos(angle), sin(angle), -sin(angle), cos(angle));
        vec2 uv = turn * (face + slope * (0.5 + 0.6 * k)) * (0.06 + 0.012 * k) + vec2(0.011, 0.006) * frameTimeCounter * (1.0 + 0.35 * k);
        // the stars are made here, one per cell of a grid at most, not read from the texture: the texture bound for the
        // portal is not always end_portal.png (a portal just lit by its last eye came with a white one, and every layer
        // lit every pixel: a pale blue sheet)
        vec2 grid = uv * END_PORTAL_CELLS;
        uvec2 c = uvec2(ivec2(floor(grid)) + 4096);
        uint h = (c.x * 1597334677u) ^ (c.y * 3812015801u) ^ (uint(i) * 2654435761u);
        h = (h ^ (h >> 16u)) * 2246822519u; h ^= h >> 13u;
        vec3 r = vec3(uvec3(h, h >> 10u, h >> 20u) & 1023u) / 1023.0;
        vec2 d = abs(fract(grid) - (0.2 + 0.6 * r.yz));
        float px = max(fwidth(grid.x), fwidth(grid.y));
        float star = (1.0 - smoothstep(END_PORTAL_STAR_SIZE, END_PORTAL_STAR_SIZE + px, max(d.x, d.y)))
                   * step(1.0 - END_PORTAL_STAR_FILL, r.x) * (0.4 + 0.6 * fract(r.x * 7.0));
        vec3 tint = mix(END_PORTAL_TINT_A, END_PORTAL_TINT_B, fract(k * 0.382));
        stars += star * tint * 1.5 / (1.0 + 0.3 * k);
    }
    return stars;
}
#endif

// blocks that get the relief from their own texture when the resource pack gives them no normal map
bool takesTexelRelief(int mat) {
    return mat != MAT_LAVA && mat != MAT_NETHER_PORTAL && mat != MAT_LEAVES && mat != MAT_FOLIAGE && mat != MAT_LEAF_LITTER && mat != MAT_PETALS && vHalfUv.x > 0.0 && vHalfUv.y > 0.0;
}

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
    // the solid terrain layer (gbuffers_terrain_solid) has no cut-out texels: without a discard the depth test runs
    // before this shader and hidden surfaces are never shaded
    #ifndef GBUF_TERRAIN_SOLID
        if (tex.a < max(alphaTestRef, 0.1)) discard;
    #endif
    #if defined GBUF_TERRAIN && !defined GBUF_TERRAIN_SOLID
        // the lit redstone torch's model wraps its head in six 3/16 block planes, each one pure red texel stretched (its
        // "aura"); as light-source texels they glowed as a pink box, rounded by the bloom. They are not
        // drawn (their red still goes to the coloured light, lib/lightcolor.glsl). Found by their
        // texel density, ~5 texels per block against 16 (from the screen derivatives: Iris' mc_midTexCoord is not the
        // quad's own centre in game), and their red
        if (vMat == MAT_EMISSIVE_TORCH && tex.r > 0.5 && max(tex.g, tex.b) < 0.35 * tex.r) {
            float texelsPerBlock = length(fwidth(vUv * vec2(textureSize(gtexture, 0)))) / max(length(fwidth(vPlayerPos)), 1e-6);
            if (texelsPerBlock < 10.0) discard;
        }
    #endif
    #ifdef GBUF_ENTITIES
        // Transparent label pixels must not write depth or auxiliary buffers.
        if (vNameTagAlpha != 0 && tex.a * vColor.a < 0.004) discard;
    #endif
    vec3 albedo = tex.rgb * vColor.rgb;   // texture x vertex tint (biome colours)
    #if defined GBUF_ENTITIES || defined GBUF_HAND
        albedo = mix(albedo, entityColor.rgb, entityColor.a);   // hurt / explosion flash
    #endif
    Material m = blockMaterial(vMat, tex.rgb);
    #if defined GBUF_ENTITIES && defined PBR_TABLE
        if (currentRenderedItemId >= 110 && currentRenderedItemId <= 116) armourMaterial(m, currentRenderedItemId, tex.rgb);
    #endif
    #if defined GBUF_ENTITIES || defined GBUF_HAND
        // light blocks as items (in a hand, dropped, in a frame): they glow as the placed block does, texel by texel,
        // with the same emissive test (a torch's handle and a lantern's cage stay as they are). For an item that places
        // a block Iris gives the block's id (block.properties), not an item id
        if (currentRenderedItemId == MAT_EMISSIVE_TORCH || currentRenderedItemId == MAT_EMISSIVE_FULL)
            m.emissive = blockMaterial(currentRenderedItemId, tex.rgb).emissive;
        m.emissive = max(m.emissive, markedGlow);
    #endif
    // metal / gem blocks, obsidian and ores: the material texel by texel (lib/surface.glsl texelDetailMaterial)
    #if defined PBR_TABLE && defined GBUF_TERRAIN
        bool texelDetail = vMat == MAT_ORE || vMat == MAT_ORE_GEM || vMat == MAT_METAL || vMat == MAT_GEM || vMat == MAT_OBSIDIAN || vMat == MAT_ICE;
        if (texelDetail && vHalfUv.x > 0.0 && vHalfUv.y > 0.0) texelDetailMaterial(m, vMat, tex.rgb, spriteMeanLumSat(gtexture, vMidUv, vHalfUv));
    #endif
    vec3 tsNormal = vec3(0.0, 0.0, 1.0);
    bool hasTextureSet = false;
    #ifndef GBUF_HAND
        hasTextureSet = textureSetMaterial(specular, normals, vUv, m, tsNormal);
    #endif

    vec3 geoNormal = gl_FrontFacing ? normalize(vNormal) : -normalize(vNormal);
    vec3 N = geoNormal;
#ifdef MOD_COMPAT
    if (vCompatFallback != 0 && !mcCompatNormalOK(geoNormal)) {
        geoNormal = compatFace;
        N = geoNormal;
    }
    if (vCompatFallback == 2) {
        // Confirmed custom entities: same Shiroi light/shadow path, plain material.
        m = defaultMaterial();
        hasTextureSet = false;
        tsNormal = vec3(0.0, 0.0, 1.0);
    }
#endif

    #if defined GBUF_BLOCK || defined GBUF_ENTITIES
        // after the mod compatibility fallback, which would give it the plain material
        if (vMat == MAT_NETHER_PORTAL) {
            // a black, matte surface: the stars are added after the shading, as light of their own, so neither the
            // block light (15 there) nor the hue of a nearby light (the lava under the portal) brightens or tints them
            hasTextureSet = false;
            albedo = vec3(0.0);
            m = Material(0.0, 0.0, 1.0, 0.0);
        }
    #endif
    bool normalMapped = hasTextureSet && tsNormal.z < 0.9999;
    if (normalMapped) N = normalize(derivativeFrame(geoNormal, vPlayerPos, vUv) * tsNormal);
    #if defined MICRO_DETAIL && defined GBUF_TERRAIN
        else if (takesTexelRelief(vMat))
            N = normalize(derivativeFrame(geoNormal, vPlayerPos, vUv) * texelRelief(gtexture, vUv, vMidUv, vHalfUv));
    #endif


#ifdef MOD_COMPAT
    if (vCompatFallback != 0) {
        if (!mcCompatNormalOK(N)) N = geoNormal;
        if (any(isnan(albedo)) || any(isinf(albedo))) albedo = mcCompatColor(albedo);
        if (!mcCompatFinite(m.metal) || !mcCompatFinite(m.emissive) ||
            !mcCompatFinite(m.roughness) || !mcCompatFinite(m.sss)) m = defaultMaterial();
    }
#endif
    #ifdef GBUF_TERRAIN
        // the eye is the element raised above the frame's top (13/16 to 16/16 of the block); the frame's top face, at
        // 13/16, has the same greens and stays unlit (the point is taken just inside the surface)
        if (vMat == MAT_END_FRAME_EYE && fract(vPlayerPos.y + cameraPosition.y - geoNormal.y * 0.004) < 13.0 / 16.0)
            m.emissive = 0.0;
    #endif
    outAlbedo = encodeAlbedo(albedo, m.metal, m.sss);
    outNormal = encodeNormals(N, geoNormal, m.roughness, m.emissive);
    outLight = encodeLighting(vLm, vMat, SURFACE_DEFERRED);

    #ifdef GBUF_FORWARD
        bool hand = vMat == MAT_HAND;
        Surface s;
        s.albedo = srgbToLinear(albedo);
        s.metal = m.metal;
        s.sss = m.sss;
        s.roughness = m.roughness;
        s.emissive = m.emissive;
        s.blockLevel = vLm.x;
        s.skyLevel = vLm.y;
        s.normal = N;
        s.flatNormal = geoNormal;
        s.pos = vPlayerPos;
        s.viewDepth = hand ? 0.0 : -(gbufferModelView * vec4(vPlayerPos, 1.0)).z;
        float dist = length(vPlayerPos);
        vec3 V = vPlayerPos / max(dist, 1e-4);
        // under water the caustics fall on mobs and players as on the terrain
        float caustics = submergedCaustics(vPlayerPos + cameraPosition, N);
        float fogT;
        KeyLightResult key;
        vec3 col = shadeSurface(s, daylight(), V, dist, skyIrradianceNow(), vec4(0.0), caustics, fogT, key);
        #ifdef IRIS_INLINE_GLINT
            if (mc_hasGlint()) col += glintRadiance(mc_sampleGlint()) * (1.0 - fogT);
        #endif
        #if defined GBUF_BLOCK || defined GBUF_ENTITIES
            if (vMat == MAT_NETHER_PORTAL) col += endPortalStars(vPlayerPos, geoNormal) * END_PORTAL_BRIGHTNESS * (1.0 - fogT);
        #endif
        outLight.w = SURFACE_FORWARD;
        // after deferred colortex2 is the bloom glow weight, and deferred skips it for forward pixels: write no normal
        // here, or entities drawn after deferred would glow by their normal's x
        outNormal = vec4(0.0, 0.0, 0.0, 1.0);
        outColor = vec4(sanitize(col), tex.a);
        #ifdef GBUF_ENTITIES
            // Keep all existing RGB lighting; only restore the label's vertex alpha.
            if (vNameTagAlpha != 0) outColor.a *= clamp(vColor.a, 0.0, 1.0);
        #endif
        outLateDepth = vec4(0.0, 0.0, 0.0, hand ? 0.0 : 2.0 + s.viewDepth);
        outDirect = vec4((key.diffuse + key.specular) * (1.0 - fogT) / max(caustics, 1e-3), 0.0);
        #if defined GBUF_ENTITIES && defined ENTITY_MOTION
            // written last (Vitrail numbers the outputs by first write)
            outMotion = vec4(0.5, 0.5, 0.0, 0.0);
            if (vPrevPos.w > 0.999 && vNameTagAlpha == 0) {
                vec4 prevView = gbufferPreviousModelView * vec4(vPrevPos.xyz, 1.0);
                vec4 prevClip = gbufferPreviousProjection * prevView;
                vec4 curClip = gbufferProjection * (gbufferModelView * vec4(vPlayerPos, 1.0));
                vec2 motion = (curClip.xy / curClip.w - prevClip.xy / prevClip.w) * 0.5;
                if (all(lessThan(abs(motion), vec2(0.25))))
                    outMotion = vec4(motion * 2.0 + 0.5, saturate(-prevView.z / 512.0), 0.0);
            }
        #endif
    #endif
}
#endif
