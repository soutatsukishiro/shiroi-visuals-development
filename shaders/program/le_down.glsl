// Local exposure base layer (the coarse layer of program/post.glsl LE_APPLY): a 5x5 gaussian of log luminance, taps
// 4 pixels apart, at 1/8 resolution. The fragment version read 25 scattered texels per output, and neighbouring
// outputs share most of them (their taps are 8 pixels apart, so 4 of 5 tap columns repeat): with taps 4 pixels apart
// almost every read missed the texture cache and went to memory (0.8 ms at 1080p for 1/64 of the pixels). Here a
// group of 8x8 outputs reads the 19x19 lattice of taps it needs once into shared memory and sums from there: the same
// taps, weights and order, so the same result. Where the screen is not a multiple of 8 the taps of neighbouring
// outputs are not on one lattice; each output then reads its own 25 taps as before. Written to leDown, copied into
// colortex15 by the fragment pass (post.glsl LE_DOWN), which LE_APPLY reads filtered.
#include "/lib/common.glsl"
#include "/lib/exposure.glsl"

layout(local_size_x = 8, local_size_y = 8) in;
// one group per 8 x 8 outputs, i.e. 1/64 of the screen; asked with a margin (loaders round the group count
// differently), the groups past the outputs return at once
const vec2 workGroupsRender = vec2(0.15, 0.15);

uniform sampler2D colortex0;
writeonly uniform image2D leDown;

const int R = 2;                 // 5x5 taps, 4 pixels apart
#define SPAN 19                  // lattice points per axis for 8 outputs, 2i + 1 + o (a literal: Vitrail drops const from
                                 // computed initialisers)
shared float tapLog[SPAN * SPAN];

float tapAt(vec2 p, vec2 screen) {
    p = min(p, vec2(1.0) - 0.5 / screen);
    return log2(clamp(luminance(texture(colortex0, sceneUv(p)).rgb), LUM_RANGE.z, LUM_RANGE.w));
}

void main() {
    vec2 screen = vec2(viewWidth, viewHeight);
    vec2 cells = max(floor(screen * 0.125), vec2(1.0));
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    float sigma2 = float(R * R) * 0.5;
    if (any(greaterThanEqual(vec2(gl_WorkGroupID.xy * 8u), cells))) return;   // the whole group: before the barrier
    bool lattice = all(equal(cells * 8.0, screen));
    float sum = 0.0, weight = 0.0;
    if (lattice) {
        // lattice point k sits at 4k pixels; output i takes k = 2i + 1 + o
        ivec2 k0 = ivec2(gl_WorkGroupID.xy) * 16 + 1 - R;
        for (int n = int(gl_LocalInvocationIndex); n < SPAN * SPAN; n += 64) {
            ivec2 k = k0 + ivec2(n % SPAN, n / SPAN);
            tapLog[n] = tapAt(vec2(k) * 4.0 / screen, screen);
        }
        barrier();
        ivec2 base = ivec2(gl_LocalInvocationID.xy) * 2;
        for (int y = -R; y <= R; y++) for (int x = -R; x <= R; x++) {
            vec2 o = vec2(x, y);
            float w = exp(-dot(o, o) / sigma2);
            sum += w * tapLog[(base.y + y + R) * SPAN + base.x + x + R];
            weight += w;
        }
    } else {
        vec2 uv = (vec2(px) + 0.5) / cells;
        for (int y = -R; y <= R; y++) for (int x = -R; x <= R; x++) {
            vec2 o = vec2(x, y);
            float w = exp(-dot(o, o) / sigma2);
            sum += w * tapAt(uv + o * 4.0 / screen, screen);
            weight += w;
        }
    }
    if (all(lessThan(vec2(px), cells))) imageStore(leDown, px, vec4(sum / weight, 0.0, 0.0, 1.0));
}
