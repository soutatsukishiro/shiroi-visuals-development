#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL
// The cloud layer: 12 x 12-block cells, one texel of the cloud texture each, 4 blocks thick, bottom at
// cloudHeight + 0.33. The texture is the game's own (shaders.properties), so the cells are the pattern of the running
// version (that of 1.21.1 differs from that of 1.21.11 in over a third of the cells) or of a resource pack. Under Iris
// the clouds always arrive as the faces of cloud cells: up to 1.21.1 Sodium replaces the vanilla clouds with its own
// cell geometry (no texture coordinates), later versions draw cells themselves.
// The cell grid scrolls along +X (0.03 blocks per tick, repeating after 256 cells = 3072 blocks) and is shifted along Z:
// 3.96 blocks in vanilla's renderer, 0.33 in Sodium's.
//
// Iris hands the X scroll over as cloudTime. The Z shift, and the X scroll where cloudTime is missing (Vitrail), are
// measured from the cloud geometry, which the vertex stage sees every frame whether or not a cloud is on screen:
//  * the corners of the faces lie on the cell grid, which gives both shifts within one cell (the Z shift never goes
//    past one cell);
//  * for the whole cells of the X scroll: a side face that looks along -X or +X stands between a cloud cell and an
//    empty one, so each sampled corner of such a face says "cloud on this side, none on that side" for one of the two
//    rows it touches; of the 256 possible shifts, only the true one satisfies every sample.
// gbuffers_clouds gathers, program/cloudtrack.glsl solves after the clouds are drawn, and the frames in between
// extrapolate at cloud speed.
#include "/lib/common.glsl"

uniform float cloudTime;
uniform float cloudHeight;
uniform sampler2D cloudTex;

const float CLOUD_THICKNESS = 4.0;
const float CLOUD_CELL = 12.0;
const float CLOUD_Z_SHIFT = 3.96;    // vanilla's; the measured one replaces it when they differ
const float CLOUD_SPEED = 0.6;       // blocks per second
const float CLOUD_PERIOD = 3072.0;
const int CLOUD_SAMPLES = 64;

// what this frame's cloud vertices wrote (bits of 'seen')
const uint SEEN_PHASE = 1u, SEEN_BOTTOM = 4u;

layout(std430, binding = 1) buffer CloudTrack {
    uint phase;          // X scroll within one cell, from this frame's corners (cloudTrackKey, smallest wins)
    uint phaseZ;         // Z shift within one cell, from this frame's corners (cloudTrackKey, smallest wins)
    uint bottom;         // world height of the layer bottom (cloudTrackKey, smallest wins)
    float scroll;        // solved X scroll (0..3072 blocks) at time 'stamp'
    float stamp;         // frameTimeCounter of that solution
    float layerBottom;   // last measured layer bottom
    float zShift;        // last measured Z shift (0: none yet)
    uint seen;
    uint solved;         // 1 once a solution exists
    uint count;          // corners sampled this frame
    uint pad0;
    uint pad1;
    vec4 samples[CLOUD_SAMPLES];   // corners of side faces: world x, z, the face's normal x
} cloudTrack;

// Many vertices report the same corner value with different float rounding. A plain store kept whichever vertex wrote
// last, which changed from run to run (the solved grid jittered by a few ulps, cloud edges flickered): every report
// goes through atomicMax of an order-preserving key of the inverted value, so the smallest reported value wins and
// 0 (the reset value) means nothing reported.
uint cloudTrackKey(float v) { uint b = floatBitsToUint(v); return ~(b ^ ((b & 0x80000000u) != 0u ? 0xFFFFFFFFu : 0x80000000u)); }
float cloudTrackValue(uint k) { uint b = ~k; return uintBitsToFloat(b ^ ((b & 0x80000000u) != 0u ? 0x80000000u : 0xFFFFFFFFu)); }

bool cloudGridKnown() { return cloudTime != 0.0 || cloudTrack.solved != 0u; }

// scroll of the cell grid along X, in blocks
float cloudScroll() {
    if (cloudTime != 0.0 || cloudTrack.solved == 0u) return cloudTime;
    float dt = frameTimeCounter - cloudTrack.stamp;
    if (dt < 0.0) dt += 3600.0;   // frameTimeCounter wraps after an hour
    return mod(cloudTrack.scroll + dt * CLOUD_SPEED, CLOUD_PERIOD);
}

// shift of the cell grid along Z: vanilla's unless the clouds drawn sit elsewhere (Sodium's)
float cloudZShift() {
    float z = cloudTrack.zShift;
    return z > 0.0 && abs(z - CLOUD_Z_SHIFT) > 0.05 ? z : CLOUD_Z_SHIFT;
}

float cloudLayerBottom() {
#ifdef MOD_COMPAT
    #ifndef SHADOW_SINGLE_PASS
        if (mcCompatDimensionInfo() && !(cloudHeight > 1.0)) {
            if (cloudTrack.layerBottom > 1.0) return cloudTrack.layerBottom;
            return float(bedrockLevel) + float(heightLimit) * (2.0 / 3.0) + 0.33;
        }
    #endif
#endif

    if (cloudHeight > 1.0) return cloudHeight + 0.33;
    return cloudTrack.layerBottom > 1.0 ? cloudTrack.layerBottom : 192.33;
}
#define CLOUD_HEIGHT cloudLayerBottom()

vec2 cloudGridPos(vec2 worldXZ) { return worldXZ + vec2(cloudScroll(), cloudZShift()); }

// whether a cell of the grid (any integers, the texture repeats) holds a cloud
bool cloudCell(ivec2 cell) {
    ivec2 n = textureSize(cloudTex, 0);
    ivec2 m = n - 1;
    // power-of-two sizes (the game's 256 x 256): the same wrapped cell with a mask instead of two integer divisions
    ivec2 wrapped = all(equal(n & m, ivec2(0))) ? cell & m : (cell % n + n) % n;
    return texelFetch(cloudTex, wrapped, 0).a >= 0.5;
}

// ------------------------------------------------------------------ gathering (gbuffers_clouds vertex stage)
void cloudTrackVertex(vec3 worldPos, vec3 normal) {
    vec2 phase = mod(-worldPos.xz, CLOUD_CELL);
    if (abs(normal.y) > 0.5) {
        // corners of top and bottom faces
        if (normal.y < 0.0) { atomicMax(cloudTrack.bottom, cloudTrackKey(worldPos.y)); atomicOr(cloudTrack.seen, SEEN_BOTTOM); }
        atomicMax(cloudTrack.phase, cloudTrackKey(phase.x));
        atomicMax(cloudTrack.phaseZ, cloudTrackKey(phase.y));
        atomicOr(cloudTrack.seen, SEEN_PHASE);
        return;
    }
    if (abs(normal.x) < 0.5) return;
    // about one corner in 31, a different subset each frame, spread over the whole cloud field
    ivec2 corner = ivec2(round((worldPos.xz + phase) / CLOUD_CELL));
    if (uint(corner.x * 7 + corner.y * 13 + frameCounter) % 31u != 0u) return;
    uint i = atomicAdd(cloudTrack.count, 1u);
    if (i < uint(CLOUD_SAMPLES)) cloudTrack.samples[i] = vec4(worldPos.xz, normal.x, 0.0);
}

#endif
