// Shadow pass: renders the cascades of lib/shadowmap.glsl into the tiles of the 2x2 shadow atlas.
//  * geometry-shader instancing: one invocation per cascade
//  * a triangle goes into cascade c only when it lies entirely inside that tile: nothing leaks into the
//    neighbouring tile, so the fragment shader needs no clipping and solid geometry keeps early depth testing
//  * triangles entirely inside the part served by the finer cascade are skipped in the coarser ones (receivers
//    read the shadow map straight along the light, so those texels would never be sampled)
//  * both tests are made per corner in the vertex stage (bit masks); the geometry stage, which runs once per cascade
//    for every triangle and is the cost of this pass, only ANDs the three masks and emits no more than the fragment
//    stage reads: the position for opaque terrain (depth only), the texture coordinate and alpha for the rest
//  * SHADOW_SINGLE_PASS (no geometry stage, see lib/common.glsl): the vertex stage projects straight into the one
//    cascade that fills the map, and the geometry stage only passes the triangle on, in the exact shape Vitrail folds
//    away (corners copied in a loop of three, nothing else)
#include "/lib/common.glsl"
#define SHADOWMAP_NO_SAMPLER
#define SHADOWMAP_NO_CLOUDS
#include "/lib/shadowmap.glsl"

#ifdef VERTEX_SHADER
in vec4 mc_Entity;
#if defined SHADOW_SINGLE_PASS && defined SHIROI_VITRAIL_SINGLE_CASCADE
// no geometry stage in this edition: the fragment stage reads these directly
out vec2 gTexcoord;
out vec4 gColor;
#elif defined SHADOW_SINGLE_PASS
out vec2 vTexcoord;
out vec4 vColor;
#else
#ifndef SHADOW_SOLID
out vec2 vTexcoord;
out float vAlpha;
#endif
out vec3 vShadowPos;   // shadow model-view space
flat out int vCascades;   // bit c: inside cascade c's tile, bit 4 + c: inside the part cascade c skips; 0: water
#endif
void main() {
    #if defined SHADOW_SINGLE_PASS && defined SHIROI_VITRAIL_SINGLE_CASCADE
        gTexcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
        gColor = gl_Color;
    #elif defined SHADOW_SINGLE_PASS
        vTexcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
        vColor = gl_Color;
    #elif !defined SHADOW_SOLID
        vTexcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
        vAlpha = gl_Color.a;
    #endif
    bool water = int(mc_Entity.x + 0.5) == MAT_WATER;   // the water surface does not cast shadows
    #ifdef SHADOW_SINGLE_PASS
        vec3 clip = cascadeClip(shadowSpace((shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz), 0);
        // a water triangle has all three corners outside the clip volume and is dropped by the rasteriser
        gl_Position = water ? vec4(2.0, 2.0, 0.0, 1.0) : vec4(clip.xy, clamp(clip.z, -1.0, 1.0), 1.0);
    #else
        vShadowPos = shadowSpace((shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz);
        // a triangle lies inside a square when its three corners do (the per-axis bounds of the corners)
        int cascades = 0;
        for (int c = 0; c < CASCADES; c++) {
            float extent = cascadeExtent(c);
            if (all(greaterThanEqual(vShadowPos.xy, vec2(-extent))) && all(lessThanEqual(vShadowPos.xy, vec2(extent)))) cascades |= 1 << c;
            if (c > 0) {
                float skip = cascadeSkipExtent(c);
                if (all(greaterThan(vShadowPos.xy, vec2(-skip))) && all(lessThan(vShadowPos.xy, vec2(skip)))) cascades |= 16 << c;
            }
        }
        vCascades = water ? 0 : cascades;
        gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
    #endif
}
#endif

#ifdef GEOMETRY_SHADER
#ifdef SHADOW_SINGLE_PASS
layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;
in vec2 vTexcoord[];
in vec4 vColor[];
out vec2 gTexcoord;
out vec4 gColor;
void main() {
    for (int i = 0; i < 3; i++) {
        gl_Position = gl_in[i].gl_Position;
        gTexcoord = vTexcoord[i];
        gColor = vColor[i];
        EmitVertex();
    }
    EndPrimitive();
}
#else
#if SHADOW_QUALITY == 0
layout(triangles, invocations = 1) in;
#elif SHADOW_QUALITY == 1
layout(triangles, invocations = 3) in;
#else
layout(triangles, invocations = 4) in;
#endif
layout(triangle_strip, max_vertices = 3) out;
in vec3 vShadowPos[];
flat in int vCascades[];
#ifndef SHADOW_SOLID
in vec2 vTexcoord[];
in float vAlpha[];
out vec2 gTexcoord;
out float gAlpha;
#endif
void main() {
    int c = gl_InvocationID;
    // inside this cascade's tile and not wholly inside the part it skips (water: no bit set)
    int m = vCascades[0] & vCascades[1] & vCascades[2];
    if ((m & (1 << c)) == 0 || (m & (16 << c)) != 0) return;
    vec2 tile = cascadeTile(c);
    for (int k = 0; k < 3; k++) {
        vec3 clip = cascadeClip(vShadowPos[k], c);
        #ifndef SHADOW_SOLID
            gTexcoord = vTexcoord[k];
            gAlpha = vAlpha[k];
        #endif
        gl_Position = vec4(tile * 2.0 + clip.xy * 0.5 - 0.5, clamp(clip.z, -1.0, 1.0), 1.0);
        EmitVertex();
    }
    EndPrimitive();
}
#endif
#endif

#ifdef FRAGMENT_SHADER
#ifdef SHADOW_SOLID
void main() { }   // depth only
#else
uniform sampler2D gtexture;
in vec2 gTexcoord;
#ifdef SHADOW_SINGLE_PASS
in vec4 gColor;
float vertexAlpha() { return gColor.a; }
#else
in float gAlpha;
float vertexAlpha() { return gAlpha; }
#endif
void main() {
    if (texture(gtexture, gTexcoord).a * vertexAlpha() < 0.1) discard;   // cutout holes do not cast shadows
}
#endif
#endif
