#ifndef SURFACE_GLSL
#define SURFACE_GLSL
// Surface detail and material of the block textures.
//  * texel-edge relief (MICRO_DETAIL): every texel is a flat tile at a height = its luminance. Within a narrow band
//    (1/6 of a texel, centred on each texel edge) the normal tilts by the height step between the two texels:
//    n = normalize(h_left - h_right, h_top - h_bottom, 0.25). The band is box-filtered over the pixel footprint and
//    the relief fades out once a texel is smaller than a pixel (mip level 1 -> 2).
//  * tangent frame from screen-space derivatives
//  * material: the texture set of the resource pack (Iris PBR atlases) or, without one, a per-block fallback
#include "/lib/common.glsl"
#include "/lib/look.glsl"

const float RELIEF_BAND_LO = 5.0 / 12.0, RELIEF_BAND_HI = 7.0 / 12.0;   // band position around an edge at 0.5
const float RELIEF_FLATNESS = 0.25;                                     // z of the unnormalised relief normal

// height of a texel of the sprite (coordinates wrap inside it); cutout holes return -1 (no height)
float texelHeight(sampler2D tex, ivec2 t, ivec2 spriteMin, ivec2 spriteSize) {
    ivec2 w = spriteMin + ((t - spriteMin) % spriteSize + spriteSize) % spriteSize;
    vec4 c = texelFetch(tex, w, 0);
    return c.a < 0.1 ? -1.0 : luminance(c.rgb);
}
// a hole takes the height of its neighbour, so hole edges of leaves and plants do not become cliffs
float fillHole(float h, float neighbour) { return h < 0.0 ? neighbour : h; }

// share of the pixel footprint [f - w/2, f + w/2] inside the relief band of edge k (k + band)
float bandShare(float f, float w, float k) {
    if (w < 1e-4) return (f >= k + RELIEF_BAND_LO && f < k + RELIEF_BAND_HI) ? 1.0 : 0.0;
    float a = max(f - 0.5 * w, k + RELIEF_BAND_LO), b = min(f + 0.5 * w, k + RELIEF_BAND_HI);
    return max(b - a, 0.0) / w;
}

// tangent-space normal (x along +u, y along +v, z out of the surface)
vec3 texelRelief(sampler2D tex, vec2 uv, vec2 midUv, vec2 halfUv) {
    vec2 size = vec2(textureSize(tex, 0));
    vec2 p = uv * size;
    vec2 ddxP = dFdx(p), ddyP = dFdy(p);
    float lod = 0.5 * log2(max(dot(ddxP, ddxP), dot(ddyP, ddyP)));
    float fade = saturate(2.0 - max(lod, 0.0));
    if (fade <= 0.0) return vec3(0.0, 0.0, 1.0);
    ivec2 spriteMin = ivec2(floor((midUv - halfUv) * size + 0.5));
    ivec2 spriteSize = max(ivec2(floor(halfUv * 2.0 * size + 0.5)), ivec2(1));
    // q: texel coordinates relative to texel centres; f in [0, 1) between the centres i0 and i0 + 1
    vec2 q = p - 0.5;
    ivec2 i0 = ivec2(floor(q));
    vec2 f = q - vec2(i0);
    int row = f.y > 0.5 ? i0.y + 1 : i0.y, col = f.x > 0.5 ? i0.x + 1 : i0.x;
    // four heights along the row and along the column through the pixel's texel
    float r0 = texelHeight(tex, ivec2(i0.x - 1, row), spriteMin, spriteSize);
    float r1 = texelHeight(tex, ivec2(i0.x, row), spriteMin, spriteSize);
    float r2 = texelHeight(tex, ivec2(i0.x + 1, row), spriteMin, spriteSize);
    float r3 = texelHeight(tex, ivec2(i0.x + 2, row), spriteMin, spriteSize);
    float c0 = texelHeight(tex, ivec2(col, i0.y - 1), spriteMin, spriteSize);
    float c1 = texelHeight(tex, ivec2(col, i0.y), spriteMin, spriteSize);
    float c2 = texelHeight(tex, ivec2(col, i0.y + 1), spriteMin, spriteSize);
    float c3 = texelHeight(tex, ivec2(col, i0.y + 2), spriteMin, spriteSize);
    r1 = fillHole(r1, max(r2, 0.0)); r2 = fillHole(r2, r1); r0 = fillHole(r0, r1); r3 = fillHole(r3, r2);
    c1 = fillHole(c1, max(c2, 0.0)); c2 = fillHole(c2, c1); c0 = fillHole(c0, c1); c3 = fillHole(c3, c2);
    vec2 w = max(abs(dFdx(q)), abs(dFdy(q)));   // pixel footprint in texels
    float sx = bandShare(f.x, w.x, -1.0) * (r0 - r1) + bandShare(f.x, w.x, 0.0) * (r1 - r2) + bandShare(f.x, w.x, 1.0) * (r2 - r3);
    float sy = bandShare(f.y, w.y, -1.0) * (c0 - c1) + bandShare(f.y, w.y, 0.0) * (c1 - c2) + bandShare(f.y, w.y, 1.0) * (c2 - c3);
    vec3 n = normalize(vec3(vec2(sx, sy) * MICRO_DETAIL_STRENGTH, RELIEF_FLATNESS));
    n.xy *= fade;
    return n;
}

// Tangent frame from screen-space derivatives. In the tangent plane, the gradients of u and v form the dual basis
// of the position derivatives (dp1, dp2): grad u = (du1 (dp2 x N) + du2 (N x dp1)) / (N . (dp1 x dp2)), same for v
// [Cramer's rule]. The common factor 1 / (N . (dp1 x dp2)) is dropped (its sign stays with the frame of mirrored
// UVs) because the pair is rescaled so that the longer vector has unit length.
mat3 derivativeFrame(vec3 N, vec3 p, vec2 uv) {
    vec3 dp1 = dFdx(p), dp2 = dFdy(p);
    vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
    vec3 e1 = cross(dp2, N), e2 = cross(N, dp1);
    vec3 gu = e1 * duv1.x + e2 * duv2.x;
    vec3 gv = e1 * duv1.y + e2 * duv2.y;
    float scale = inversesqrt(max(max(dot(gu, gu), dot(gv, gv)), 1e-20));
    return mat3(gu * scale, gv * scale, N);
}

struct Material { float metal; float emissive; float roughness; float sss; };

Material defaultMaterial() { return Material(DEFAULT_MATERIAL.x, DEFAULT_MATERIAL.y, DEFAULT_MATERIAL.z, DEFAULT_MATERIAL.w); }

// fallback when the resource pack has no texture set for the block: light sources glow by their texel brightness,
// foliage / snow / ice / wool let light through, glass stays clear; optional rough guesses per block family
Material blockMaterial(int id, vec3 texSrgb) {
    Material m = defaultMaterial();
    float lum = luminance(texSrgb);
    float mx = max(texSrgb.r, max(texSrgb.g, texSrgb.b));
    float mn = min(texSrgb.r, min(texSrgb.g, texSrgb.b));
    float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
    if (id == MAT_LEAVES || id == MAT_FOLIAGE) m.sss = 1.0;
    else if (id == MAT_SNOW) m.sss = 0.6;
    else if (id == MAT_ICE) m.sss = 0.3;
    else if (id == MAT_WOOL) m.sss = 0.15;
    else if (id == MAT_LEAF_LITTER || id == MAT_PETALS) m.sss = 0.5;   // fallen leaves and petals let the light through
    else if (id == MAT_EMISSIVE_FULL)  m.emissive = smoothstep(0.25, 0.85, mx);
    // froglights, shroomlight, magma, glow lichen, crying obsidian: the same test, a third as bright (glowstone glows
    // about three times as much from its surface; all of them still light the area through the light level)
    else if (id == MAT_EMISSIVE_SOFT)  m.emissive = smoothstep(0.25, 0.85, mx) * EMISSIVE_SOFT_SHARE;
    else if (id == MAT_EMISSIVE_TORCH) m.emissive = smoothstep(0.55, 0.92, mx) * smoothstep(0.15, 0.4, sat + lum * 0.5);
    // glowing details (lit redstone parts, sculk, trial spawner and vault): the coloured texels only; the flame test
    // above also took in bright grey texels (a comparator's stone, a rail's iron). On a sculk catalyst only the bright
    // cyan texels pass, not the bone. A sculk shrieker's swirl is a darker teal: fully saturated, green over red and not
    // bluer than green, which keeps out the deep blue of sculk around it
    else if (id == MAT_GLOW_DETAIL)    m.emissive = max(smoothstep(0.45, 0.75, mx) * smoothstep(0.3, 0.55, sat),
        smoothstep(0.18, 0.22, mx) * smoothstep(0.93, 0.97, sat) * smoothstep(-0.04, 0.0, texSrgb.g - texSrgb.b)
        * smoothstep(0.15, 0.2, texSrgb.g - texSrgb.r));
    // light sources that glow only in part: the near-white texels (a jack o'lantern's face, a copper bulb's lamp, an
    // end rod's rod), or the bright, fully saturated ones (crying obsidian's tears, a respawn anchor's charge). Green
    // copper bulbs add their warm lamp texels, as bright as the verdigris around them but much redder
    else if (id == MAT_EMISSIVE_CORE || id == MAT_EMISSIVE_CORE_WARM) {
        m.emissive = max(smoothstep(0.9, 0.97, mx), smoothstep(0.55, 0.65, mx) * smoothstep(0.9, 0.95, sat));
        if (id == MAT_EMISSIVE_CORE_WARM) m.emissive = max(m.emissive, smoothstep(0.6, 0.7, mx) * smoothstep(0.35, 0.45, texSrgb.r - texSrgb.b));
    }
    // the eye of ender in a frame: a dull green, too grey for the colour test above. Green clearly above red glows, the
    // dark pupil does not; the frame's own top has the same greens, so gbuffers_solid keeps the glow to the raised eye
    else if (id == MAT_END_FRAME_EYE)  m.emissive = smoothstep(0.08, 0.16, texSrgb.g - texSrgb.r) * smoothstep(0.25, 0.38, mx);
    // the spawner's eyes: two dark magenta texels (#6E0453), too dark for the colour test above. Only they are this
    // saturated with red and blue well over green; the cage's blues stay under 0.5 saturation
    else if (id == MAT_SPAWNER)        m.emissive = smoothstep(0.7, 0.85, sat) * smoothstep(0.1, 0.22, min(texSrgb.r, texSrgb.b));
    else if (id == MAT_LAVA || id == MAT_NETHER_PORTAL) m.emissive = 1.0;
    else if (id == MAT_GLASS) m.roughness = 0.05;
    #ifdef PBR_TABLE
    if (id == MAT_STONE)            { m.roughness = mix(0.92, 0.72, lum); }
    else if (id == MAT_POLISHED)    { m.roughness = mix(0.62, 0.42, lum); }
    else if (id == MAT_DIRT)        { m.roughness = 0.97; }
    else if (id == MAT_GRASS_BLOCK) { m.roughness = 0.9; m.sss = 0.0; }
    else if (id == MAT_SAND)        { m.roughness = mix(0.95, 0.8, lum); }
    // the sprite-relative materials at their texel's mean roughness; gbuffers_solid refines it texel by texel
    // (spriteRelativeRoughness) where the sprite's mean is known
    else if (id == MAT_WOOD)        { m.roughness = 0.80; }
    else if (id == MAT_WOOD_SMOOTH) { m.roughness = 0.567; }
    else if (id == MAT_MUD)         { m.roughness = 0.513; }
    else if (id == MAT_PACKED_MUD)  { m.roughness = 0.711; }
    else if (id == MAT_MUD_BRICKS)  { m.roughness = 0.583; }
    else if (id == MAT_MUDDY_ROOTS) { m.roughness = 0.768; }
    else if (id == MAT_BLACKSTONE)  { m.roughness = 0.77; }
    else if (id == MAT_POLISHED_BLACKSTONE) { m.roughness = 0.61; }
    // gilded blackstone as in the target look: the whole stone a little metallic (0.25), its gold flecks (the only
    // saturated texels; all 37 found on the vanilla texture) metal 0.75 and smoother
    else if (id == MAT_GILDED_BLACKSTONE) {
        float gold = smoothstep(0.4, 0.65, sat);
        m.metal = 0.25 + 0.5 * gold;
        m.roughness = mix(0.88, 0.55, gold);
    }
    else if (id == MAT_WOOL)        { m.roughness = 1.0; }
    else if (id == MAT_LEAVES)      { m.roughness = 0.706; }
    else if (id == MAT_FOLIAGE)     { m.roughness = 0.8; }
    // roughness against the texel's luminance: wet farmland smooth (0.22-0.68, the dark soil smoothest), dry farmland rough; the petals of
    // the cherry grove fairly smooth; melon smoother than pumpkin
    else if (id == MAT_FARMLAND_WET) { m.roughness = clamp(0.848 - 1.394 * lum, 0.22, 0.68); }
    else if (id == MAT_FARMLAND)     { m.roughness = clamp(1.237 - 0.959 * lum, 0.71, 0.99); }
    else if (id == MAT_LEAF_LITTER)  { m.roughness = clamp(0.216 + 0.823 * lum, 0.44, 0.94); }
    else if (id == MAT_PETALS)       { m.roughness = clamp(0.991 - 0.663 * lum, 0.41, 0.72); }
    else if (id == MAT_MELON)        { m.roughness = clamp(0.895 - 0.61 * lum, 0.51, 0.69); }
    else if (id == MAT_PUMPKIN)      { m.roughness = clamp(1.278 - 1.081 * lum, 0.51, 0.98); }
    else if (id == MAT_SNOW)        { m.roughness = 0.85; }
    else if (id == MAT_ICE)         { m.roughness = 0.08; }
    else if (id == MAT_GLASS)       { m.roughness = 0.05; }
    else if (id == MAT_METAL || id == MAT_SPAWNER) { m.metal = 1.0 - m.emissive; m.roughness = mix(0.5, 0.25, lum); }
    else if (id == MAT_GEM || id == MAT_OBSIDIAN) { m.roughness = 0.12; m.metal = 0.0; }
    else if (id == MAT_ORE) {
        float speck = smoothstep(0.25, 0.5, sat) * smoothstep(0.25, 0.45, lum);   // saturated / bright texels: mineral
        m.roughness = mix(0.88, 0.3, speck);
        m.metal = speck;
    }
    else if (id == MAT_ORE_GEM) {
        float speck = smoothstep(0.2, 0.45, sat) * smoothstep(0.2, 0.4, lum);
        m.roughness = mix(0.88, 0.15, speck);
    }
    else if (id == MAT_EMISSIVE_FULL || id == MAT_EMISSIVE_CORE || id == MAT_EMISSIVE_CORE_WARM || id == MAT_EMISSIVE_SOFT) { m.roughness = 0.6; }
    else if (id == MAT_EMISSIVE_TORCH) { m.roughness = 0.7; }
    else if (id == MAT_LAVA)           { m.roughness = 0.4; }
    else if (id == MAT_NETHER_PORTAL)  { m.roughness = 0.2; }
    #endif
    return m;
}

#include "/lib/sprite_mean.glsl"

// Material texel by texel for metal blocks, gem blocks, obsidian and ores (PBR_TABLE, terrain).
// Each family follows a line in the texel luminance: the bright texels (iron plates, the relief of obsidian, the
// mineral of an ore) are smoother, the grooves and the stone rougher, so only parts of a block reflect and catch the light, texel by texel.
// Leaves, wood, mud and blackstone: in the target look each texture's roughness is its own brightness mapped onto one range per
// family (all planks 0.71-0.99, bright texels smoothest), not one line of absolute brightness for the family. So the
// texel's luminance is taken against its own sprite (spriteLumStats: mean, darkest, brightest, saturation). Leaves,
// wood and blackstone: from the darkest to the brightest texel across the family's range; mud: base + slope x (lum - mean),
// which follows it closer there. Fitted per family on the target look's texture sets against the game's textures
// (mean error per texel 0.01-0.07; muddy mangrove roots 0.1, their pattern is not in the brightness). Leaves with their
// own colour (cherry, poplar: saturated sprites, not tinted by the biome) are smoother.
void spriteRelativeRoughness(inout Material m, int id, vec3 texSrgb, vec4 sprite) {
    float lum = luminance(texSrgb);
    float t = saturate((lum - sprite.y) / max(sprite.z - sprite.y, 0.02));   // 0 darkest .. 1 brightest
    if (id == MAT_LEAVES)           m.roughness = mix(mix(0.89, 0.78, smoothstep(0.25, 0.4, sprite.w)), 0.41, t);
    else if (id == MAT_WOOD)        m.roughness = mix(0.93, 0.71, t);
    else if (id == MAT_WOOD_SMOOTH) m.roughness = mix(0.68, 0.44, t);
    else if (id == MAT_BLACKSTONE)  m.roughness = mix(0.89, 0.61, t);
    else if (id == MAT_POLISHED_BLACKSTONE) m.roughness = mix(0.75, 0.41, t);
    else {
        vec4 r;   // base, slope, lowest, highest
        if (id == MAT_MUD)             r = vec4(0.513, -3.951, 0.24, 0.66);
        else if (id == MAT_PACKED_MUD) r = vec4(0.711, -1.687, 0.61, 0.89);
        else if (id == MAT_MUD_BRICKS) r = vec4(0.583, -1.531, 0.41, 0.79);
        else                           r = vec4(0.768, -0.830, 0.49, 0.89);   // muddy mangrove roots
        m.roughness = clamp(r.x + r.y * (lum - sprite.x), r.z, r.w);
    }
}

// The lines here are fitted per family against the block's own mean (spriteMeanLumSat): metal blocks metal 0.75,
// roughness 0.22..0.85; obsidian 0.42..0.81 with some metal (a dark, tinted sheen); gem blocks 0.22..0.68; ice
// 0.22..0.68 (its white streaks the smoothest, never a mirror; ice, packed, blue and frosted ice alike). In an ore
// the mineral is found by being brighter or more saturated than the block: mineral 0.22..0.5, stone 0.7..0.89, the
// mineral of iron / gold / copper ores partly metallic.
void texelDetailMaterial(inout Material m, int id, vec3 texSrgb, vec2 mean) {
    float d = luminance(texSrgb) - mean.x;
    float mx = max(texSrgb.r, max(texSrgb.g, texSrgb.b)), mn = min(texSrgb.r, min(texSrgb.g, texSrgb.b));
    float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
    if (id == MAT_ORE || id == MAT_ORE_GEM) {
        float mineral = max(smoothstep(0.06, 0.2, d), smoothstep(0.2, 0.4, sat - mean.y));
        m.roughness = mix(clamp(0.8 - 0.6 * d, 0.7, 0.89), clamp(0.42 - d, 0.22, 0.5), mineral);
        m.metal = id == MAT_ORE ? mineral * clamp(0.65 * sat, 0.0, 0.5) : 0.0;
        return;
    }
    // base roughness, slope against d, range
    if (id == MAT_SPAWNER) id = MAT_METAL;   // its glowing eye texels stay out of the metal (emissive is kept)
    vec4 r = id == MAT_METAL ? vec4(0.52, 1.2, 0.22, 0.85) : (id == MAT_OBSIDIAN ? vec4(0.68, 1.65, 0.42, 0.81)
           : (id == MAT_ICE ? vec4(0.57, 2.2, 0.22, 0.68) : vec4(0.5, 0.8, 0.22, 0.68)));
    m.roughness = clamp(r.x - r.y * d, r.z, r.w);
    m.metal = id == MAT_METAL ? 0.75 * (1.0 - m.emissive) : (id == MAT_OBSIDIAN ? clamp(0.34 - 2.0 * d, 0.0, 0.53) : 0.0);
}

// Armour pieces: metal and roughness against the texel's luminance, the bright plates smoothest. Ids from item.properties, given by
// Iris' currentRenderedItemId while an equipment layer is drawn. Leather is left as it is.
void armourMaterial(inout Material m, int id, vec3 texSrgb) {
    float l = luminance(texSrgb);
    vec4 r;        // roughness: at luminance 0, per unit of luminance, lowest, highest
    float metal;
    if (id == 110)      { r = vec4(1.414, -1.287, 0.41, 0.76); metal = 0.75; }   // chainmail
    else if (id == 111) { r = vec4(1.166, -0.757, 0.41, 0.62); metal = 0.75; }   // iron
    else if (id == 112) { r = vec4(1.178, -0.831, 0.21, 0.65); metal = 0.75; }   // gold
    else if (id == 113) { r = vec4(1.349, -1.096, 0.21, 0.64); metal = 0.75; }   // diamond
    else if (id == 114) { r = vec4(0.825, -0.883, 0.45, 0.79); metal = 0.5; }    // netherite
    else if (id == 115) { r = vec4(1.001, -0.888, 0.38, 0.95); metal = 0.0; }    // turtle shell
    else                { r = vec4(1.309, -1.335, 0.22, 0.82); metal = 0.64; }   // copper
    m.roughness = clamp(r.x + r.y * l, r.z, r.w);
    m.metal = metal;
}

// texture set from Iris' PBR atlases (same layout as the colour atlas). PBR_FORMAT 0, the layout of this pack's own
// PBR resource packs:
//   specular: R metalness, G emissive, B 1 - roughness, A 1   (Iris fills sprites without one with black: A 0)
//   normals : RG tangent-space normal (0.5 = flat), B 1 - subsurface
// PBR_FORMAT 1, LabPBR 1.3 (most PBR resource packs):
//   specular: R perceptual smoothness, G F0 (230-255: metals), B porosity (0-64) / subsurface (65-255),
//             A emissive (0-254; 255 is none)
//   normals : RG tangent-space normal, B ambient occlusion (not used), A height (not used)
// Read in the other layout a LabPBR pack lost its emission (it is in A) and made every metal glow (G = 230+).
// Emissive keeps the fallback's light-block value as a floor (the pack's emissive is low on light blocks).
bool textureSetMaterial(sampler2D spec, sampler2D nrm, vec2 uv, inout Material m, out vec3 tsNormal) {
    tsNormal = vec3(0.0, 0.0, 1.0);
    vec4 s = texture(spec, uv);
    #if PBR_FORMAT == 1
        if (dot(s, s) < 1e-6) return false;   // a sprite without a specular map
        vec4 n = texture(nrm, uv);
        float smoothness = s.r;
        m.roughness = (1.0 - smoothness) * (1.0 - smoothness);
        m.metal = step(229.5 / 255.0, s.g);
        m.emissive = max(s.a < 254.5 / 255.0 ? s.a * (255.0 / 254.0) : 0.0, m.emissive);
        m.sss = s.b > 64.5 / 255.0 ? (s.b * 255.0 - 65.0) / 190.0 : 0.0;
    #else
        if (s.a < 0.5) return false;
        vec4 n = texture(nrm, uv);
        m.metal = s.r;
        m.emissive = max(s.g, m.emissive);
        m.roughness = 1.0 - s.b;
        m.sss = 1.0 - n.b;
    #endif
    vec2 xy = n.rg * 2.0 - 1.0;
    if (dot(xy, xy) > 4e-4) tsNormal = vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
    return true;
}

#endif
