#version 430 compatibility
#define BLOOM_UP
#define BLOOM_SRC colortex9
#define BLOOM_SELF colortex8
#define BLOOM_SCALE 0.5
#define FRAGMENT_SHADER
/* RENDERTARGETS: 8 */
#include "/program/post.glsl"
