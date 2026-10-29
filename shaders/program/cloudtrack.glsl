// Cloud tracking (see lib/clouds.glsl): runs after the clouds are drawn. Keeps the Z shift the corners give, then finds
// the whole cells of the X scroll: one thread per candidate shift checks the sampled side-face corners; under the true
// shift each one has, in one of the two rows it touches, a cloud texel on its inner side and an empty one on its outer
// side. A shift is taken only when it alone explains every usable sample. Then the gathering state is reset.
#include "/lib/common.glsl"
#include "/lib/clouds.glsl"
// the shadow grid state is stored here too: this pass runs once per frame, after every shadow lookup
#define SHADOWMAP_NO_SAMPLER
#include "/lib/shadowmap.glsl"
#include "/lib/motion.glsl"

layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(1, 1, 1);
shared uint hits[256];

// the face at grid column x, looking towards -X (west) or +X (east), has cloud behind it and none in front of it
bool edgeInRow(int x, int row, bool west) {
    bool left = cloudCell(ivec2(x - 1, row)), right = cloudCell(ivec2(x, row));
    return west ? (right && !left) : (left && !right);
}

void main() {
    uint shift = gl_LocalInvocationIndex;
    uint seen = cloudTrack.seen;
    vec2 phase = vec2(cloudTrackValue(cloudTrack.phase), cloudTrackValue(cloudTrack.phaseZ));
    uint n = min(cloudTrack.count, uint(CLOUD_SAMPLES));
    uint used = 0u, hit = 0u;
    if ((seen & SEEN_PHASE) != 0u) {
        for (uint s = 0u; s < n; s++) {
            vec4 corner = cloudTrack.samples[s];
            vec2 g = (corner.xy + phase) / CLOUD_CELL;
            vec2 r = round(g);
            if (any(greaterThan(abs(g - r), vec2(0.02)))) continue;   // not on the grid (should not happen)
            used++;
            ivec2 c = ivec2(r) + ivec2(int(shift), 0);
            bool west = corner.z < 0.0;
            if (edgeInRow(c.x, c.y - 1, west) || edgeInRow(c.x, c.y, west)) hit++;
        }
    }
    hits[shift] = hit;
    barrier();
    if (shift != 0u) return;

    if ((seen & SEEN_PHASE) != 0u) {
        cloudTrack.zShift = max(phase.y, 1e-3);
        uint best = 0u, second = 0u, bestShift = 0u;
        for (uint k = 0u; k < 256u; k++) {
            uint h = hits[k];
            if (h > best) { second = best; best = h; bestShift = k; }
            else if (h > second) second = h;
        }
        if (used >= 16u && best == used && second < used) {
            cloudTrack.scroll = mod(float(bestShift) * CLOUD_CELL + phase.x, CLOUD_PERIOD);
            cloudTrack.stamp = frameTimeCounter;
            cloudTrack.solved = 1u;
        }
    }
    if ((seen & SEEN_BOTTOM) != 0u) cloudTrack.layerBottom = cloudTrackValue(cloudTrack.bottom);
    cloudTrack.seen = 0u;
    cloudTrack.phase = 0u;
    cloudTrack.phaseZ = 0u;
    cloudTrack.bottom = 0u;
    cloudTrack.count = 0u;
    if (gl_LocalInvocationIndex == 0u) { storeShadowGrid(); storeCloudShadowStep(); storePlayerMotion(); }
}
