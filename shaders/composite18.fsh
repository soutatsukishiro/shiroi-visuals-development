#version 430 compatibility
#define BLOOM_UP
#define BLOOM_SRC colortex13
#define BLOOM_SELF colortex12
#define BLOOM_SCALE 0.03125
#define FRAGMENT_SHADER
/* RENDERTARGETS: 12 */
#include "/program/post.glsl"
