#ifndef ENTITYMOTION_GLSL
#define ENTITYMOTION_GLSL
// Motion vectors of entities (R16). Iris 1.11.7 gives no per-entity motion or previous transform, so the pack tracks
// the entity vertices itself: every frame each vertex of gbuffers_entities writes its camera-relative position into a
// hash table (key: entity type id + texture coordinate, bucket: that key and the 4-block world cell), and looks the
// same key up in the previous frame's table, in the 27 cells around it, taking the nearest entry. That gives where the
// vertex was, so walking mobs, other players and swinging limbs reproject correctly in the TAA. Two tables, ping-pong
// by frame parity; composite32 clears the one the next frame writes. A key can be ambiguous (two mobs of one type in
// one spot, mirrored limbs sharing texture coordinates): the nearest previous position wins; no match = no vector, and
// the TAA falls back on its clip as before.
#ifdef ENTITY_MOTION
const uint TRACK_SLOTS = 32768u;   // per table (power of two)
const float TRACK_CELL = 4.0;      // blocks
const int TRACK_PROBES = 8;
layout(std430, binding = 4) buffer EntityTrack {
    uvec4 slot[];                  // [2 * TRACK_SLOTS]: x key (0 = empty), yzw camera-relative position (float bits)
} entityTrack;

uint trackHash(uint x) { x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16; return x; }
uint trackKey(int id, vec2 uv) {
    uvec2 q = uvec2(clamp(uv, 0.0, 1.0) * 16384.0 + 0.5);
    return trackHash(uint(id) * 0x9E3779B9u ^ q.x * 0x85EBCA6Bu ^ q.y * 0xC2B2AE35u) | 1u;
}
uint trackBucket(uint key, ivec3 cell) {
    return (key ^ trackHash(uint(cell.x) * 73856093u ^ uint(cell.y) * 19349663u ^ uint(cell.z) * 83492791u)) & (TRACK_SLOTS - 1u);
}
ivec3 trackCell(vec3 worldPos) { return ivec3(floor(worldPos / TRACK_CELL)); }

// vertex stage: record this vertex, return its camera-relative position of the previous frame (w 0: unknown)
vec4 trackEntityVertex(int id, vec2 uv, vec3 playerPos) {
    uint key = trackKey(id, uv);
    uint cur = uint(frameCounter & 1) * TRACK_SLOTS, prev = TRACK_SLOTS - cur;
    ivec3 cell = trackCell(playerPos + cameraPosition);
    uint b = trackBucket(key, cell);
    for (int i = 0; i < TRACK_PROBES; i++) {
        uint s = cur + ((b + uint(i)) & (TRACK_SLOTS - 1u));
        uint was = atomicCompSwap(entityTrack.slot[s].x, 0u, key);
        if (was == 0u) { entityTrack.slot[s].yzw = floatBitsToUint(playerPos); break; }
        // the same key is also used by other corners of the model (box unwrap: faces share texture coordinates):
        // only the very same vertex (drawn again) may reuse the slot, any other takes the next one
        if (was == key && all(equal(entityTrack.slot[s].yzw, floatBitsToUint(playerPos)))) break;
    }
    // previous frame: the nearest entry with this key; its position is relative to the previous camera
    vec3 camMove = cameraPosition - previousCameraPosition;
    float best = 4.0;   // squared blocks: no vertex moves 2 blocks in a frame
    vec4 found = vec4(0.0);
    for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        uint pb = trackBucket(key, cell + ivec3(x, y, z));
        for (int i = 0; i < TRACK_PROBES; i++) {
            uvec4 e = entityTrack.slot[prev + ((pb + uint(i)) & (TRACK_SLOTS - 1u))];
            if (e.x == 0u) break;
            if (e.x != key) continue;
            vec3 p = uintBitsToFloat(e.yzw);
            vec3 d = playerPos + camMove - p;   // world move of the vertex
            float d2 = dot(d, d);
            if (d2 < best) { best = d2; found = vec4(p, 1.0); }
        }
    }
    return found;
}
#endif
#endif
