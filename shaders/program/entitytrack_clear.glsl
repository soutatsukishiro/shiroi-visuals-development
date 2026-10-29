// End of frame: clear the entity tracking table the next frame writes (lib/entitymotion.glsl). That table was the
// "previous" one of this frame, read during this frame's gbuffers only.
#include "/lib/common.glsl"
#include "/lib/entitymotion.glsl"
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(128, 1, 1);
void main() {
    #ifdef ENTITY_MOTION
        uint next = uint((frameCounter + 1) & 1) * TRACK_SLOTS;
        entityTrack.slot[next + gl_GlobalInvocationID.x] = uvec4(0u);
    #endif
}
