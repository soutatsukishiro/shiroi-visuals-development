#version 430 compatibility
#define BLOOM_DOWN
#define BLOOM_SRC colortex0
#define BLOOM_SCALE 0.5
#define BLOOM_FIRST
#define FRAGMENT_SHADER
/* RENDERTARGETS: 8 */
#include "/program/post.glsl"
