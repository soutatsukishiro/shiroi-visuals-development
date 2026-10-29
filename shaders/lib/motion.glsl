#ifndef MOTION_GLSL
#define MOTION_GLSL
// Motion of the player's own body (R15). Iris 1.11.7 gives no motion vectors and no previous transform per entity,
// so the TAA reprojected every entity as if it stood still in the world. That is wrong for the player seen in third
// person: it moves with the camera, so its history was looked up where it no longer is, failed the clip and was
// dropped, and the walking player shimmered. The player's eye is known (relativeEyePosition = camera - eye, computed
// in double by Iris); its camera-relative position of the previous frame is kept here (written once per frame by
// composite31, after every reader), and the entity pixels inside the player's box are reprojected with the eye's move.
// Its limbs' own animation is not known: that part still falls back on the TAA's clip.
uniform vec3 relativeEyePosition;
layout(std430, binding = 3) buffer PlayerMotionState {
    vec4 prevEye;    // xyz: eye - camera of the previous frame, w: 1 when it was a third-person view
} playerMotion;

vec3 playerEyeOffset() { return -relativeEyePosition; }   // the eye, camera-relative (player space)
// a third-person view now and in the previous frame (in first person the eye is the camera: offset 0)
bool playerMoveKnown() {
    vec3 move = playerEyeOffset() - playerMotion.prevEye.xyz;
    return playerMotion.prevEye.w > 0.5 && dot(relativeEyePosition, relativeEyePosition) > 1e-4 && dot(move, move) < 4.0;
}
// a camera-relative point inside the player's body: within 0.8 blocks of the eye across, 1.9 below to 0.6 above it
bool inPlayerBody(vec3 p) {
    vec3 d = p - playerEyeOffset();
    return dot(d.xz, d.xz) < 0.64 && d.y > -1.9 && d.y < 0.6;
}
// camera-relative position in the previous frame of a point that moves with the player
vec3 playerPointPrevious(vec3 p) { return p - (playerEyeOffset() - playerMotion.prevEye.xyz); }
void storePlayerMotion() {
    playerMotion.prevEye = vec4(playerEyeOffset(), dot(relativeEyePosition, relativeEyePosition) > 1e-4 ? 1.0 : 0.0);
}
#endif
