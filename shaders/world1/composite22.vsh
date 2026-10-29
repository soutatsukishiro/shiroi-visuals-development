#version 430 compatibility
#define DIM_END
#define BLOOM_UP
#define BLOOM_SRC colortex9
#define BLOOM_SELF colortex8
#define BLOOM_SCALE 0.5
#define VERTEX_SHADER
#include "/program/post.glsl"
