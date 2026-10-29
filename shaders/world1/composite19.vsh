#version 430 compatibility
#define DIM_END
#define BLOOM_UP
#define BLOOM_SRC colortex12
#define BLOOM_SELF colortex11
#define BLOOM_SCALE 0.0625
#define VERTEX_SHADER
#include "/program/post.glsl"
