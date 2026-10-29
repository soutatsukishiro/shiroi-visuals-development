// Disc mask of the sun and moon, accumulated over frames (runs right after the TAA resolve, before the bloom).
// The celestial glow (post.glsl CELESTIAL_BLEND) is added around the discs but not on them, to keep their own look.
// That test read the raster mask (colortex2.a), which follows the TAA jitter, after the TAA: a pixel on the edge of
// the disc, or where the player's arm crosses it, was disc in some frames and not in others, so it alternately got
// the glow and lacked it, a dark line flickering round the disc (worse at 85% internal resolution). Here the share of
// disc samples at the stable pixel position is accumulated like the TAA colour: reprojected along the view direction
// (the discs are at infinity), clipped to the range of the current samples (an edge that really moved is taken at
// once), 0.9 of history. The glow then uses 1 - share: 0 on the disc, 1 around it, as before, and steady at the edge.
#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16) in;
const vec2 workGroupsRender = vec2(1.0, 1.0);

uniform sampler2D colortex2;   // a: celestial source weight, on the raster (jittered) grid
writeonly uniform image2D celestialA;
writeonly uniform image2D celestialB;
uniform sampler2D celestialASampler;
uniform sampler2D celestialBSampler;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    vec2 screen = vec2(viewWidth, viewHeight);
    if (any(greaterThanEqual(px, ivec2(screen)))) return;
    bool even = (frameCounter & 1) == 0;
    float share = 0.0;
    #if defined TAA && defined BLOOM && SUN_LIGHT_BLEED == 1
        vec2 uv = (vec2(px) + 0.5) / screen;
        // the raster samples around the stable position (the same position post.glsl stableGlowMetadata reads)
        vec2 halfPixel = 0.5 / sceneSize();
        vec2 p = sceneUv(clamp(uv + taaJitterPixels() / sceneSize(), halfPixel, vec2(1.0) - halfPixel));
        vec4 disc = vec4(greaterThan(textureGather(colortex2, p, 3), vec4(0.0)));   // x (0,1) y (1,1) z (1,0) w (0,0)
        vec2 f = fract(p * screen - 0.5);
        float current = mix(mix(disc.w, disc.z, f.x), mix(disc.x, disc.y, f.x), f.y);
        float lo = min(min(disc.x, disc.y), min(disc.z, disc.w)), hi = max(max(disc.x, disc.y), max(disc.z, disc.w));
        share = current;
        // previous position of this view direction
        vec3 dir = mat3(gbufferModelViewInverse) * screenToView(uv, 1.0);
        vec4 clip = gbufferPreviousProjection * vec4(mat3(gbufferPreviousModelView) * dir, 0.0);
        vec2 prevUv = clip.xy / max(clip.w, 1e-5) * 0.5 + 0.5;
        if (frameCounter > 1 && clip.w > 0.0 && all(greaterThan(prevUv, vec2(0.0))) && all(lessThan(prevUv, vec2(1.0)))) {
            float history = even ? texture(celestialBSampler, prevUv).r : texture(celestialASampler, prevUv).r;
            share = mix(current, clamp(history, lo, hi), 0.9);
        }
    #endif
    if (even) imageStore(celestialA, px, vec4(share));
    else imageStore(celestialB, px, vec4(share));
}
