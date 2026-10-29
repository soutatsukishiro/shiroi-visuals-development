#version 430 compatibility
#define DIM_END
#define BLOOM_UP
#define BLOOM_SRC colortex11
#define BLOOM_SELF colortex10
#define BLOOM_SCALE 0.125
#define FRAGMENT_SHADER
/* RENDERTARGETS: 10 */
#include "/program/post.glsl"
