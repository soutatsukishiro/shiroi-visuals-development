#ifndef GBUFFER_GLSL
#define GBUFFER_GLSL
// Render targets and the G-buffer layout.
//   colortex0  RGBA16F  HDR colour
//   colortex1  RGBA16F  albedo (sRGB) + metal / subsurface byte   (after deferred: water texture layer, or the colour of the
//                       translucents in front of the water: gbuffers_translucent)
//   colortex2  RGBA16   shading normal (octahedral), roughness | emissive, geometric normal (octahedral, 2 x 8 bit)
//                                                                         (after deferred: emissive glow weight)
//   colortex3  RGBA8    block light, sky light, material id, surface flag (1 G-buffer, 0.5 forward-shaded, 0 none)
//   colortex4  RGBA16   water surface: normal, roughness, sky light (alpha 0 = no water)
//   colortex5  RGBA16F  sun / moon / stars (or an entity's direct light), alpha: particle coverage
//   colortex6  RGBA16F  previous frame RGB (unsharpened, before local exposure), alpha: TAA view depth
//   colortex7  RGBA16F  overlays (glint) -> direct light after deferred; alpha: depth of surfaces drawn late
//   colortex8..13 RGBA16F bloom levels 1/2 .. 1/64 (alpha: emissive luminance on the way down)
//   colortex14 RGBA16F  sky probe atlas (256 x 128)
//   colortex15 RG16F    local exposure gaussian (1/8)
/*
const int colortex0Format = RGBA16F;
const int colortex1Format = RGBA16F;
const int colortex2Format = RGBA16;
const int colortex3Format = RGBA8;
const int colortex4Format = RGBA16;
const int colortex5Format = RGBA16F;
const int colortex6Format = RGBA16F;
const int colortex7Format = RGBA16F;
const int colortex8Format = RGBA16F;
const int colortex9Format = RGBA16F;
const int colortex10Format = RGBA16F;
const int colortex11Format = RGBA16F;
const int colortex12Format = RGBA16F;
const int colortex13Format = RGBA16F;
const int colortex14Format = RGBA16F;
const int colortex15Format = RG16F;
*/
const bool colortex4Clear = true;
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex5Clear = true;
const vec4 colortex5ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex6Clear = false;
const bool colortex7Clear = true;
const vec4 colortex7ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const bool colortex14Clear = false;
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

// two 8-bit values in one 16-bit channel
float pack2x8(vec2 v) { vec2 q = floor(clamp(v, 0.0, 1.0) * 255.0 + 0.5); return (q.x * 256.0 + q.y) / 65535.0; }
vec2 unpack2x8(float p) { float x = floor(p * 65535.0 + 0.5); return vec2(floor(x / 256.0), mod(x, 256.0)) / 255.0; }

// metal and subsurface share one byte (a surface is one or the other): bytes 128..255 carry metal 0..1, bytes 127..0
// carry subsurface 0..1, so both have an exact zero; the larger of the two is kept
const float BYTE_STEP = 0.498039216;   // 127 / 255
const float METAL_ZERO = 0.5019608;    // 128 / 255
float packMetalSss(float metal, float sss) { return sss < metal ? metal * BYTE_STEP + METAL_ZERO : BYTE_STEP - sss * BYTE_STEP; }
float unpackMetal(float a) { return saturate((a - METAL_ZERO) * 2.007874); }   // 255 / 127
float unpackSss(float a) { return saturate((BYTE_STEP - a) * 2.007874); }

// colortex3.w: how the pixel gets its colour
const float SURFACE_DEFERRED = 1.0;   // shaded by the deferred pass from the G-buffer
const float SURFACE_FORWARD = 0.5;    // shaded where it was drawn, colour already in colortex0
// (0: nothing written, the sky)

// albedo kept at 8 bits per channel, as the textures are (colortex1 is RGBA16F for its use after deferred)
vec4 encodeAlbedo(vec3 albedoSrgb, float metal, float sss) { return floor(saturate(vec4(albedoSrgb, packMetalSss(metal, sss))) * 255.0 + 0.5) / 255.0; }
// xy: shading normal, z: roughness | emissive, w: geometric normal (2 x 8 bit, for the shadow offset)
vec4 encodeNormals(vec3 N, vec3 geoNormal, float roughness, float emissive) {
    return vec4(octEncode(N) * 0.5 + 0.5, pack2x8(vec2(roughness, emissive)), pack2x8(octEncode(geoNormal) * 0.5 + 0.5));
}
vec4 encodeLighting(vec2 lightmap, int materialId, float surfaceKind) { return vec4(lightmap, float(materialId) / 255.0, surfaceKind); }
int materialIdOf(vec4 lighting) { return int(lighting.z * 255.0 + 0.5); }

struct GBufferTexel {
    vec3 albedoSrgb;
    float metal, sss, roughness, emissive;
    vec3 normal, geoNormal;
    vec2 lightmap;
    int materialId;
};
GBufferTexel decodeGBuffer(vec4 albedo, vec4 normals, vec4 lighting) {
    GBufferTexel g;
    g.albedoSrgb = albedo.rgb;
    g.metal = unpackMetal(albedo.a);
    g.sss = unpackSss(albedo.a);
    vec2 re = unpack2x8(normals.z);
    g.roughness = re.x;
    g.emissive = re.y;
    g.normal = octDecode(normals.xy * 2.0 - 1.0);
    g.geoNormal = octDecode(unpack2x8(normals.w) * 2.0 - 1.0);
    g.lightmap = lighting.xy;
    g.materialId = materialIdOf(lighting);
    return g;
}

#endif
