#version 430 compatibility
#define DIM_NETHER
#define BLOOM_UP
#define BLOOM_SRC colortex10
#define BLOOM_SELF colortex9
#define BLOOM_SCALE 0.25
#define FRAGMENT_SHADER
/* RENDERTARGETS: 9 */
#include "/program/post.glsl"
