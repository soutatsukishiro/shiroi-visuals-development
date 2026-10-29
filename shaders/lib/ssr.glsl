#ifndef SSR_GLSL
#define SSR_GLSL
// Screen-space reflections: the reflected ray is marched through the depth buffer in screen space, about one pixel
// per step up to SSR_STEPS steps, with per-pixel jitter; the first crossing within the thickness is refined by
// bisection [McGuire & Mara 2014]. The hit fades out near the screen edges, towards the end of the ray and with
// roughness. The colour comes from the previous frame, reprojected.
#include "/lib/common.glsl"
#include "/lib/look.glsl"

const int SSR_BISECTION_STEPS = 12;
const float SSR_EDGE_SHARPNESS = 8.0;   // exponent of the screen-edge fade

// distance along the view axis of a depth-buffer value (through the projection matrix: Minecraft's far plane is
// four times the render distance, so the `far` uniform cannot be used here)
float viewAxisDepth(float d) {
    return gbufferProjection[3][2] / ((d * 2.0 - 1.0) + gbufferProjection[2][2]);
}

// xy: hit uv, w: reflection weight (w < 0: no hit)
vec4 traceScreenReflection(sampler2D depthTex, vec3 viewPos, vec3 viewNormal, float roughness, float jitter) {
    const vec4 MISS = vec4(0.0, 0.0, 0.0, -1.0);
    if (roughness > SSR_ROUGH_CUTOFF) return MISS;
    vec3 dir = normalize(reflect(normalize(viewPos), viewNormal));
    vec3 origin = viewPos + viewNormal * 0.02;
    vec3 target = origin + dir;
    if (target.z > -near) target = origin + dir * ((-near - origin.z) / dir.z) * 0.99;   // stay in front of the near plane
    vec3 a = viewToScreen(origin), b = viewToScreen(target);
    // Depth belongs to jittered raster coordinates; the history is on a stable grid.
    #ifdef TAA
        a.xy += taaJitterPixels() / sceneSize();
        b.xy += taaJitterPixels() / sceneSize();
    #endif
    vec3 step1 = b - a;
    float pixels = max(abs(step1.x * sceneSize().x), abs(step1.y * sceneSize().y));
    if (pixels < 1e-4) return MISS;
    step1 /= pixels;   // one pixel
    // number of one-pixel steps before the ray leaves the screen (or the depth range)
    vec3 toBorder = mix((1.0 - a) / step1, -a / step1, step(step1, vec3(0.0)));
    float budget = max(min(toBorder.x, min(toBorder.y, toBorder.z)), 0.0);
    float stride = max(1.0, budget / float(SSR_STEPS));
    vec3 stepVec = step1 * stride;
    int steps = int(min(budget / stride, float(SSR_STEPS)));

    float rayDepthBefore = viewAxisDepth(a.z);
    float tBefore = 0.0, tHit = -1.0;
    vec3 hit = vec3(0.0);
    for (int i = 1; i <= steps; i++) {
        float t = float(i) - 0.5 + jitter;   // jittered start removes the stair-step banding
        vec3 p = a + stepVec * t;
        float rayDepth = viewAxisDepth(p.z);
        float d = texture(depthTex, sceneUv(p.xy)).r;
        float sceneDepth = viewAxisDepth(d);
        // crossed the scene surface, and the scene was not far in front of the previous ray point (thickness)
        if (d < 1.0 && rayDepth >= sceneDepth && sceneDepth * (1.0 + SSR_THICKNESS) >= rayDepthBefore) { hit = p; tHit = t; break; }
        rayDepthBefore = rayDepth;
        tBefore = t;
    }
    if (tHit < 0.0) return MISS;
    float lo = tBefore, hi = tHit;
    for (int k = 0; k < SSR_BISECTION_STEPS; k++) {
        float mid = (lo + hi) * 0.5;
        vec3 p = a + stepVec * mid;
        if (viewAxisDepth(texture(depthTex, sceneUv(p.xy)).r) < viewAxisDepth(p.z)) { hit = p; hi = mid; } else lo = mid;
    }
    vec2 edge = abs(hit.xy * 2.0 - 1.0);
    float edgeFade = (1.0 - pow(edge.x, SSR_EDGE_SHARPNESS)) * (1.0 - pow(edge.y, SSR_EDGE_SHARPNESS));
    float along = hi / max(float(steps), 1.0);
    float lengthFade = 1.0 - smoothstep01(saturate((along - SSR_FADE_LENGTH) / (1.0 - SSR_FADE_LENGTH)));
    float roughFade = 1.0 - (max(roughness, SSR_ROUGH_FADE_START) - SSR_ROUGH_FADE_START) / (SSR_ROUGH_CUTOFF - SSR_ROUGH_FADE_START);
    return vec4(hit.xy, 0.0, min(min(edgeFade, lengthFade), roughFade));
}

// where a screen point was in the previous frame
vec2 previousScreenUv(vec2 uv, float depth) {
    #ifdef TAA
        vec3 player = viewToPlayer(rasterToView(uv, depth)) + cameraPosition - previousCameraPosition;
    #else
        vec3 player = viewToPlayer(screenToView(uv, depth)) + cameraPosition - previousCameraPosition;
    #endif
    vec4 clip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(player, 1.0));
    return (clip.xy / clip.w) * 0.5 + 0.5;
}

#endif
