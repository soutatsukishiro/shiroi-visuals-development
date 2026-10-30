// Native-resolution temporal resolve. RGB history is unsharpened, pre-exposure;
// its previously unused alpha stores view depth (negative for the hand, sky sentinel).
// No new render target/pass. All helpers are compiled only in LE_APPLY.
vec3 taaEncode(vec3 rgb) {
    rgb = sanitize(rgb);
    rgb /= 1.0 + luminance(rgb);
    return vec3(dot(rgb, vec3(0.25, 0.5, 0.25)), (rgb.r - rgb.b) * 0.5,
                dot(rgb, vec3(-0.25, 0.5, -0.25)));
}
vec3 taaDecode(vec3 ycc) {
    vec3 rgb = max(vec3(ycc.x + ycc.y - ycc.z, ycc.x + ycc.z, ycc.x - ycc.y - ycc.z), 0.0);
    return sanitize(rgb / max(1.0 - luminance(rgb), 1e-4));
}

vec3 taaHistory(vec2 uv) {
    vec2 p = uv * screenSize() - 0.5;
    vec2 f = fract(p), centre = floor(p) + 0.5;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 mid = w1 + w2;
    vec2 lo = (centre - 1.0) / screenSize(), hi = (centre + 2.0) / screenSize();
    vec2 t = (centre + w2 / mid) / screenSize();
    vec3 a = texture(colortex6, vec2(t.x,lo.y)).rgb, b = texture(colortex6, vec2(lo.x,t.y)).rgb;
    vec3 m = texture(colortex6, t).rgb;
    vec3 d = texture(colortex6, vec2(hi.x,t.y)).rgb, e = texture(colortex6, vec2(t.x,hi.y)).rgb;
    vec3 c = a * mid.x * w0.y + b * w0.x * mid.y + m * mid.x * mid.y + d * w3.x * mid.y + e * mid.x * w3.y;
    c = sanitize(c / (mid.x*w0.y + w0.x*mid.y + mid.x*mid.y + w3.x*mid.y + mid.x*w3.y));
    // the negative lobes of the cubic overshoot at a hard edge (a dark rim beside the sun or lava): bounded by the
    // five bilinear reads it is made of. Bilinear reads instead, there, blurred the history a little every frame in
    // motion, which added up (the moving picture went soft)
    return clamp(c, min(min(a, b), min(m, min(d, e))), max(max(a, b), max(m, max(d, e))));
}

vec3 taaSafeHistory(vec2 uv, float expectedDepth, float tolerance, bool sky, bool hand, vec3 fallback) {
    vec2 p = uv * screenSize() - 0.5;
    ivec2 base = ivec2(floor(p));
    vec2 f = fract(p);
    vec3 sum = vec3(0.0);
    float total = 0.0;
    for (int i = 0; i < 4; ++i) {
        ivec2 o = ivec2(i & 1, i >> 1);
        vec4 sampleValue = texelFetch(colortex6, clamp(base + o, ivec2(0), ivec2(screenSize()) - 1), 0);
        bool sameKind = sky ? sampleValue.a < -65000.0
            : (hand ? sampleValue.a < 0.0 && sampleValue.a > -65000.0 : sampleValue.a > 0.0);
        bool accepted = sameKind && (sky || abs(abs(sampleValue.a) - expectedDepth) < tolerance);
        vec2 w = mix(vec2(1.0) - f, f, vec2(o));
        float weight = accepted ? w.x * w.y : 0.0;
        sum += sanitize(sampleValue.rgb) * weight;
        total += weight;
    }
    return total > 1e-5 ? sum / total : fallback;
}

vec3 temporalResolve(vec2 uv, vec3 raw, out vec3 display, out float storedDepth) {
    #ifdef SHIROI_UPSCALE
        // Reconstruct at the native pixel centre from the jittered internal grid.
        vec2 samplePosition = uv * sceneSize() - 0.5 + taaJitterPixels();
        ivec2 px = clamp(ivec2(floor(samplePosition + 0.5)), ivec2(0), ivec2(sceneSize()) - 1);
        ivec2 limit = ivec2(sceneSize()) - 1;
        vec2 filterOffset = samplePosition - vec2(px);
    #else
        ivec2 px = ivec2(gl_FragCoord.xy), limit = ivec2(screenSize()) - 1;
        vec2 filterOffset = taaJitterPixels();
    #endif
    vec4 flag = texelFetch(colortex3, px, 0);
    int material = int(flag.z * 255.0 + 0.5);
    float depth = texelFetch(depthtex0, px, 0).r;
    float late = texelFetch(colortex7, px, 0).a;
    bool hand = material == MAT_HAND;
    bool sky = depth >= 1.0;
    vec3 view = screenToView(uv, depth);
    float viewDepth = max(-view.z, 0.0001);
    // Translucent entities/particles can be drawn after the depth copy.
    if (!hand && abs(late) > 1.5) {
        float front = max(abs(late) - 2.0, 0.0001);
        if (sky || front < viewDepth) { view *= front / viewDepth; viewDepth = front; sky = false; }
    }
    storedDepth = sky ? -65504.0 : (hand ? -viewDepth : viewDepth);
    display = raw;
    if (material == MAT_OUTLINE) { storedDepth = 0.0; return raw; }

    // Rasterized geometry samples uv-jitter. Reconstruct the current image at
    // the stable output pixel before accumulating a stable-grid history.
    // The same nine fetches provide clipping statistics and detail recovery.
    vec2 jitter = taaJitterPixels();
    // A reconstructed silhouette can contain both sky and an occluder. Do not
    // label that mixed colour as pure sky in next frame's depth-aware history:
    // it is stored at the occluder's depth. (It used to be stored as rejectable,
    // 0: then every silhouette pixel against the sky, which the jitter shows as
    // sky in some frames and as the object in others, dropped its history every
    // frame and flickered: the horizon, tree tops, the outline of the player.)
    bool mixedSky = false;
    float occluderDepth = 0.0;
    if (sky) {
        vec4 footprintDepth = textureGather(depthtex0, sceneUv(uv + jitter / sceneSize()), 0);
        #ifdef SHIROI_UPSCALE
            vec2 f = fract(samplePosition);
        #else
            vec2 f = fract(jitter);
        #endif
        vec4 weights = vec4((1.0-f.x)*f.y, f.x*f.y, f.x*(1.0-f.y), (1.0-f.x)*(1.0-f.y));
        vec4 solid = vec4(lessThan(footprintDepth, vec4(1.0)));
        if (any(lessThan(footprintDepth, vec4(1.0)))) {
            vec4 materialId = floor(textureGather(colortex3, sceneUv(uv + jitter / sceneSize()), 2) * 255.0 + 0.5);
            // Cutout foliage needs mixed coverage in history to remain stable.
            // (foliage is an occluder like any other: the silhouette keeps its history, R11)
        }
        float occluderShare = dot(solid, weights);
        if (occluderShare > 0.01) {
            float nearest = min(min(footprintDepth.x, footprintDepth.y), min(footprintDepth.z, footprintDepth.w));
            occluderDepth = max(-screenToView(uv, nearest).z, 0.0001);
            storedDepth = occluderDepth;
            mixedSky = true;
        }
    }
    vec3 current = vec3(0.0), mean = vec3(0.0), meanSq = vec3(0.0);
    vec3 low = vec3(1e20), high = vec3(-1e20);
    bool anySky = false, anySurface = false;
    float nearRaw = 1.0, farRaw = 0.0;   // depth range of the solid samples around (the phase hold below)
    for (int y = -1; y <= 1; ++y) for (int x = -1; x <= 1; ++x) {
        ivec2 q = clamp(px + ivec2(x,y), ivec2(0), limit);
        vec3 c = taaEncode(texelFetch(colortex0, q, 0).rgb);
        float dq = texelFetch(depthtex0, q, 0).r;
        anySky = anySky || dq >= 1.0;
        anySurface = anySurface || dq < 1.0;
        if (dq < 1.0) { nearRaw = min(nearRaw, dq); farRaw = max(farRaw, dq); }
        vec2 w = max(vec2(1.0) - abs(vec2(x,y) - filterOffset), vec2(0.0));
        current += c * w.x * w.y;
        mean += c; meanSq += c*c;
        low = min(low,c); high = max(high,c);
    }
    mean /= 9.0;
    // a silhouette against the sky (the horizon of a lake, a tree top, the outline of a player): with the jitter the
    // pixel is sky in some frames and the object in others, and each kind rejected the other's history, so these
    // edges showed the raw jittered sample every frame. Here the history of either kind is taken; the colour clip
    // below still bounds it to what the 3 x 3 neighbourhood holds now, so nothing trails more than one pixel.
    bool silhouette = anySky && anySurface && !hand;
    vec3 sigma = sqrt(max(meanSq / 9.0 - mean*mean, vec3(0.0)));
    float depthSlope = min(abs(dFdx(viewDepth)) + abs(dFdy(viewDepth)), viewDepth * 0.04);

    vec4 prevView;
    vec2 prevUv = uv;
    #ifdef ENTITY_MOTION
        vec4 entityMotionVector = vec4(0.0);
    #endif
    float expectedDepth = viewDepth;
    if (!hand) {
        if (sky) {
            // Directions at infinity rotate with the camera, but never translate.
            vec3 direction = mat3(gbufferModelViewInverse) * view;
            prevView = vec4(mat3(gbufferPreviousModelView) * direction, 0.0);
        } else {
            vec3 player = viewToPlayer(view) + cameraPosition - previousCameraPosition;
            // the player's own body seen in third person moves with the player, not with the world (lib/motion.glsl)
            if ((material == MAT_ENTITY || late > 1.5) && playerMoveKnown() && inPlayerBody(viewToPlayer(view)))
                player = playerPointPrevious(viewToPlayer(view));
            prevView = gbufferPreviousModelView * vec4(player, 1.0);
            #ifdef ENTITY_MOTION
                // an entity with a tracked vector (lib/entitymotion.glsl): where this point really was
                if (material == MAT_ENTITY || late > 1.5) {
                    vec4 m = texelFetch(colortex4, px, 0);   // written through the depth test: the visible surface's
                    if (m.a == 0.0 && m.b > 0.0) entityMotionVector = vec4((m.rg - 0.5) * 0.5, m.b * 512.0, 1.0);
                }
            #endif
        }
        vec4 clip = gbufferPreviousProjection * prevView;
        prevUv = clip.xy / max(clip.w, 1e-5) * 0.5 + 0.5;
        expectedDepth = -prevView.z;
        #ifdef ENTITY_MOTION
            if (entityMotionVector.w > 0.0) { prevUv = uv - entityMotionVector.xy; expectedDepth = entityMotionVector.z; }
        #endif
    }
    // Reject initial/invalid history, teleports, projection changes and offscreen samples.
    // only history that reprojects off the screen is lost (the history reads clamp at the edge): a 2-pixel margin
    // dropped the history of the outermost pixels every frame, and the screen's edges shimmered with the jitter
    vec2 border = 0.5 / screenSize();
    bool valid = frameCounter > 1 && expectedDepth > 0.0
        && length(cameraPosition - previousCameraPosition) < 8.0
        && abs(gbufferProjection[0][0] - gbufferPreviousProjection[0][0]) < 0.001
        && abs(gbufferProjection[1][1] - gbufferPreviousProjection[1][1]) < 0.001
        && all(greaterThan(prevUv, border)) && all(lessThan(prevUv, vec2(1.0) - border));
    // Check the footprint, not a single nearest depth. Subpixel jitter can
    // alternate leaf/background coverage even with a stationary camera.
    vec4 oldDepth = textureGather(colortex6, prevUv, 3);
    // the silhouette rule and the wider clip range below are for a still view only: in motion an edge's history
    // belongs elsewhere (taking it dragged the player's colour into the sky beside the sun)
    bool stillPixel = length((prevUv - uv) * screenSize()) < 0.25;
    bool depthMatch = false;
    for (int i = 0; i < 4; ++i) {
        if (sky) {
            // a silhouette pixel keeps its history while it stays a silhouette (the occluder's depth was stored);
            // once the edge has moved off it, it needs pure sky again, so no dark trail is pulled into the sky
            depthMatch = depthMatch || oldDepth[i] < -65000.0;
            if (mixedSky) depthMatch = depthMatch || (oldDepth[i] > 0.0 && abs(oldDepth[i] - occluderDepth) < max(0.05, occluderDepth * 0.02) + depthSlope * 1.5);
        } else {
            bool sameKind = hand ? oldDepth[i] < 0.0 && oldDepth[i] > -65000.0 : oldDepth[i] > 0.0;
            float tolerance = max(0.05, expectedDepth * 0.02) + depthSlope * 1.5;
            depthMatch = depthMatch || (sameKind && abs(abs(oldDepth[i]) - expectedDepth) < tolerance);
        }
        if (silhouette && stillPixel) depthMatch = depthMatch || oldDepth[i] < -65000.0 || oldDepth[i] > 0.0;
    }
    // A thin leaf can move to the opposite neighbouring sample in the 8-phase
    // jitter cycle. Only retry failed pixels within this one-pixel footprint.
    if (!depthMatch && !sky && !hand) {
        for (int q = 0; q < 3; ++q) {
            vec2 offset = q == 0 ? vec2(-1.0,0.0) : (q == 1 ? vec2(0.0,-1.0) : vec2(-1.0));
            vec4 nearby = textureGather(colortex6, prevUv + offset / sceneSize(), 3);
            for (int i = 0; i < 4; ++i)
                depthMatch = depthMatch || (nearby[i] > 0.0 && abs(nearby[i] - expectedDepth) < max(0.05, expectedDepth * 0.02) + depthSlope * 1.5);
        }
    }
    // Phase hold (TAA_ANTI_FLICKER). Still camera, still surface, and the depth did not match: at a cutout or texture
    // edge the nearest internal sample lands on the other surface (leaf / background) in some of the 8 jitter phases,
    // worst at 85 %. Rejecting the history there showed that phase's raw sample, and the next frames resolved from it:
    // a dip of up to 40 levels for one or two frames in eight (the TAA flicker). The target look's TAAU rejects no
    // history by depth at all: it keeps it and bounds it by the colours around (Upscaling.material TAAU). Here, where
    // the history's surface is still in the 3 x 3 neighbourhood and no actor is beside it (an edge between two still
    // surfaces, not ground uncovered by a mob that walked on), the history is kept and clipped like any other; a
    // change that stays (a block broken) is taken by the clip. (Formerly the screen showed the history for at most 2
    // frames while the history itself was still rejected: the dip came back on the next frames.)
    // per-pixel state carried with the history (ping-pong images taaFlickA / B): r unused (the old hold's run), g how
    // many frames this pixel has been still (the settle-in below)
    ivec2 prevPx = clamp(ivec2(prevUv * screenSize()), ivec2(0), ivec2(screenSize()) - 1);
    vec2 pixelState = (frameCounter & 1) == 0 ? texelFetch(taaFlickBSampler, prevPx, 0).rg : texelFetch(taaFlickASampler, prevPx, 0).rg;
    // a custom image starts uninitialised (NaN or garbage on some drivers): taken as 0
    pixelState = vec2(pixelState.x >= 0.0 && pixelState.x <= 255.0 ? pixelState.x : 0.0, pixelState.y >= 0.0 && pixelState.y <= 255.0 ? pixelState.y : 0.0);
    bool phaseMismatch = false;
    float heldDepth = 0.0;
    #ifdef TAA_ANTI_FLICKER
    if (!depthMatch && stillPixel && !sky && !hand
        && !(material == MAT_ENTITY || material == MAT_PARTICLE || material == MAT_EYES || late < -1.5)) {
        // the history's surface within the depth range of the solid samples around
        float nearView = -screenToView(uv, nearRaw).z, farView = -screenToView(uv, farRaw).z;
        float tol = max(0.05, farView * 0.02) + depthSlope * 2.0;
        for (int i = 0; i < 4; ++i)
            if (oldDepth[i] > nearView - tol && oldDepth[i] < farView + tol) heldDepth = oldDepth[i];
        // no actor beside it (the cross of four)
        bool actorNear = false;
        for (int k = 0; k < 4; ++k) {
            ivec2 q = clamp(px + (k == 0 ? ivec2(1, 0) : (k == 1 ? ivec2(-1, 0) : (k == 2 ? ivec2(0, 1) : ivec2(0, -1)))), ivec2(0), limit);
            int mq = int(texelFetch(colortex3, q, 0).z * 255.0 + 0.5);
            actorNear = actorNear || mq == MAT_ENTITY || mq == MAT_PARTICLE || mq == MAT_EYES || mq == MAT_HAND || abs(texelFetch(colortex7, q, 0).a) > 1.5;
        }
        phaseMismatch = heldDepth > 0.0 && !actorNear;
    }
    #endif
    valid = valid && (depthMatch || phaseMismatch);
    // Still camera, still surface: over the 8 jitter phases this pixel gathers samples from up to 1.5 samples away
    // (tent of radius 1 + jitter 0.5), but one frame's 3 x 3 only sees 1. On an edge (the horizon of a lake, the
    // outline of a player, a tree top) some phases saw only one side and clipped the accumulated history to it, a
    // dip every few frames. The range (history clip and the final detail clamp) also takes the samples two away.
    if (stillPixel && !(hand || material == MAT_ENTITY || material == MAT_PARTICLE || late < -1.5)) {
        for (int k = 0; k < 4; ++k) {
            ivec2 o = k == 0 ? ivec2(2, 0) : (k == 1 ? ivec2(-2, 0) : (k == 2 ? ivec2(0, 2) : ivec2(0, -2)));
            vec3 c = taaEncode(texelFetch(colortex0, clamp(px + o, ivec2(0), limit), 0).rgb);
            low = min(low, c); high = max(high, c);
        }
    }
    vec3 resolved = current;
    if (valid) {
        // the sky away from silhouettes: depth-checked bilinear history (taaSafeHistory); everything else the clamped
        // cubic (taaHistory)
        vec3 h = taaEncode(sky && !mixedSky && !(silhouette && stillPixel)
            ? taaSafeHistory(prevUv, expectedDepth, max(0.05, expectedDepth * 0.02) + depthSlope * 1.5, sky, hand, taaDecode(current))
            : taaHistory(prevUv));
        float motion = length((prevUv - uv) * screenSize());
        float clipWidth = mix(2.0, 1.25, saturate(motion / 12.0));
        vec3 lo = max(low, mean - sigma * clipWidth);
        vec3 hi = min(high, mean + sigma * clipWidth);
        vec3 centre = (lo + hi) * 0.5;
        vec3 extent = max((hi - lo) * 0.5, vec3(1e-5));
        vec3 delta = h - centre;
        vec3 excess = abs(delta) / extent;
        float outside = max(excess.x, max(excess.y, excess.z));   // > 1: the history had to be clipped into the box
        vec3 boxed = centre + delta / max(1.0, outside);
        #ifdef TAA_ANTI_FLICKER
            // a still pixel's history is clipped along the line towards the current sample, as the target look's TAAU
            // does (to where that line enters the box), not towards the box centre: on an edge whose box changes with
            // the jitter phase (the far edge of a lake against the sky) the history keeps its own side and no longer
            // dips to the middle in some phases. In motion as before
            if (outside > 1.0 && stillPixel) {
                vec3 toCurrent = current - h;
                vec3 inv = 1.0 / mix(vec3(1e-6), toCurrent, greaterThan(abs(toCurrent), vec3(1e-6)));
                vec3 t0 = (lo - h) * inv, t1 = (hi - h) * inv;
                vec3 tNear = min(t0, t1), tFar = max(t0, t1);
                float tIn = max(max(tNear.x, tNear.y), tNear.z), tOut = min(min(tFar.x, tFar.y), tFar.z);
                if (tIn <= tOut && tOut >= 0.0) boxed = h + toCurrent * clamp(tIn, 0.0, 1.0);
            }
        #endif
        h = boxed;
        float blend = min(TAA_BLEND * mix(1.0, 0.75, saturate(motion / 24.0)), mix(TAA_BLEND, 0.85, saturate(motion / 3.0)));
        // a still camera on a still surface: the history is reliable, keep more of it (the remaining jitter
        // shimmer goes from about 19 % to under 9 % of a frame's variation); anything that changes is clipped above
        bool actor = hand || material == MAT_ENTITY || material == MAT_PARTICLE || material == MAT_EYES || late < -1.5;
        // Settle-in: a still pixel's history weight grows with the frames it has been still, as n / (n + 1) from 0.75 to
        // 0.985. Right after the camera stops the soft history of the motion is
        // replaced within a few frames; it used to take the full 0.985 at once and needed some 60 frames to sharpen.
        if (!actor) {
            float n = pixelState.g + 1.0;
            blend = mix(clamp(n / (n + 1.0), 0.75, 0.985), blend, saturate(motion / 0.5));
        }
        #ifdef SHIROI_UPSCALE
            // An output pixel far from the nearest internal sample gets mostly interpolation this frame:
            // trust the history more while the camera is still (Gaussian in output pixels, floor 25%).
            float sampleDistance = length(filterOffset * screenSize() / sceneSize());
            float confidence = exp(-sampleDistance * sampleDistance / 0.245);
            confidence = mix(confidence, 1.0, saturate(motion / 0.5));
            blend = 1.0 - (1.0 - blend) * mix(0.25, 1.0, confidence);
        #endif
        bool dynamicSurface = hand || material == MAT_ENTITY || material == MAT_PARTICLE
            || material == MAT_EYES || material == MAT_LAVA || material == MAT_NETHER_PORTAL || late < -1.5;
        // Actors have no motion vectors, so their history is trusted less, but only when it had to be clipped
        // (they really moved or changed). A still player or mob kept the reduction every frame: the jitter alone
        // made its texture edges and outline shimmer.
        if (dynamicSurface && outside > 1.0) {
            float change = abs(h.x - current.x) / max(max(h.x, current.x), 0.05);
            blend = min(blend, 0.7) * (1.0 - 0.8 * saturate(change * 2.0));
        }
        resolved = mix(current, h, blend);
    }
    {
        // settled frames: counted while the pixel moves less than a pixel per frame, back to 0 when it moves more (it is
        // that motion that softens the history). The settle-in above only acts under half a pixel, so a slow drift (far
        // terrain while walking) keeps counting and keeps the full weight; a history rejected now and then on a still
        // view (a thin edge) keeps its count too, so a still picture is resolved exactly as before
        float still = length((prevUv - uv) * screenSize()) < 1.0 ? min(pixelState.g + 1.0, 255.0) : 0.0;
        if ((frameCounter & 1) == 0) imageStore(taaFlickA, ivec2(gl_FragCoord.xy), vec4(0.0, still, 0.0, 0.0));
        else imageStore(taaFlickB, ivec2(gl_FragCoord.xy), vec4(0.0, still, 0.0, 0.0));
    }
    vec3 history = taaDecode(resolved);
    // Bounded luma-only detail, excluded from feedback: no recurring sharpening,
    // no extra samples/passes, reduced on thin/high-contrast edges and moving actors.
    float contrast = high.x - low.x;
    float detail = clamp(resolved.x - mean.x, -contrast * 0.15, contrast * 0.15);
    float amount = TAA_SHARPNESS * (1.0 - smoothstep(0.1, 0.35, contrast)) * (1.0 + 2.0 * saturate(length((prevUv - uv) * screenSize()) / 2.0));
    if (hand || material == MAT_ENTITY || material == MAT_PARTICLE || late < -1.5) amount *= 0.35;
    resolved.x = clamp(resolved.x + detail * amount, low.x, high.x);
    display = taaDecode(resolved);
    return history;
}
