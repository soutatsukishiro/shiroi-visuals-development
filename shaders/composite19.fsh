#version 430 compatibility
#define BLOOM_UP
#define BLOOM_SRC colortex12
#define BLOOM_SELF colortex11
#define BLOOM_SCALE 0.0625
#define FRAGMENT_SHADER
/* RENDERTARGETS: 11 */
#include "/program/post.glsl"
