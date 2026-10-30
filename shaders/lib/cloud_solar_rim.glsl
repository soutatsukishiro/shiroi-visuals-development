#if CLOUD_SOLAR_RIM == 1 || CLOUD_MODEL == 1
#ifndef SHIROI_CLOUD_SOLAR_RIM_GLSL
#define SHIROI_CLOUD_SOLAR_RIM_GLSL
#if CLOUD_RIM_STYLE == 0
// Original perimeter-light approximation for Java's existing cloud mesh.
// Uses the pack's tracked cloud occupancy and solar curves.
// Only exposed cell edges receive light; joined cells keep their uninterrupted interior.
vec3 shiroiCloudClassicRim(vec3 worldPos, vec3 normal, vec3 viewRay, float layerBottom, Daylight light) {
    #if defined DIM_NETHER || defined DIM_END
        return vec3(0.0);
    #else
        float daylightFade = smoothstep(-0.08, 0.12, light.sun.dir.y);
        float clearWeather = (1.0 - saturate(rainStrength)) * (1.0 - saturate(thunderStrength));
        if (!cloudGridKnown() || daylightFade * clearWeather <= 0.0 || light.sun.lux <= 0.0) return vec3(0.0);
        if (any(lessThanEqual(textureSize(cloudTex, 0), ivec2(0)))) return vec3(0.0);

        // Offset into the occupied cell so a side face exactly on a grid line selects its own cell.
        vec2 grid = cloudGridPos((worldPos - normal * 0.02).xz) / CLOUD_CELL;
        ivec2 cell = ivec2(floor(grid));
        vec2 local = fract(grid) * CLOUD_CELL;
        vec4 emptyNeighbor = vec4(
            cloudCell(cell + ivec2(-1, 0)) ? 0.0 : 1.0,
            cloudCell(cell + ivec2( 1, 0)) ? 0.0 : 1.0,
            cloudCell(cell + ivec2( 0,-1)) ? 0.0 : 1.0,
            cloudCell(cell + ivec2( 0, 1)) ? 0.0 : 1.0);
        vec4 edgeDistance = vec4(local.x, CLOUD_CELL - local.x, local.y, CLOUD_CELL - local.y);
        // Bound the antialias feather in world units so distant faces do not turn solid white.
        vec2 footprint = min(fwidth(worldPos.xz), vec2(0.6));
        vec4 width = vec4(0.65) + vec4(footprint.x, footprint.x, footprint.y, footprint.y);
        #if CLOUD_RIM_STYLE == 1
            // Wider transmission falloff along exposed perimeter, without cell seams.
            width += vec4(0.65);
        #endif
        vec4 edgeBand = (vec4(1.0) - smoothstep(vec4(0.0), width, edgeDistance)) * emptyNeighbor;
        vec4 towardSun = saturate(vec4(-light.sun.dir.x, light.sun.dir.x, -light.sun.dir.z, light.sun.dir.z));
        edgeBand *= vec4(0.55) + 0.45 * towardSun;
        float perimeter = max(max(edgeBand.x, edgeBand.y), max(edgeBand.z, edgeBand.w));

        // A side face gets a narrow upper/lower trim, not a uniformly emissive wall.
        float height = clamp(worldPos.y - layerBottom, 0.0, CLOUD_THICKNESS);
        float verticalEdge = min(height, CLOUD_THICKNESS - height);
        float verticalWidth = 0.65 + min(fwidth(worldPos.y), 0.6);
        float sideTrim = 1.0 - smoothstep(0.0, verticalWidth, verticalEdge);
        #if CLOUD_RIM_STYLE == 1
            // Lit side faces keep a soft fill between their upper and lower edges.
            sideTrim = 0.30 + 0.70 * sideTrim;
        #endif
        perimeter *= mix(sideTrim, 1.0, saturate(abs(normal.y)));

        float lowSun = 1.0 - smoothstep(0.08, 0.55, light.sun.dir.y);
        float viewFocus = pow(saturate(dot(viewRay, light.sun.dir)), 6.0);
        float strength = perimeter * daylightFade * clearWeather * (0.8 + 1.8 * lowSun) * (0.55 + 1.2 * viewFocus);
        #if CLOUD_RIM_STYLE == 1
            strength *= 0.80;
        #endif
        // Sun only: its existing warm daylight curves fade continuously without switching to the moon.
        return light.sun.tint * light.sun.lux * (0.45 * INV_PI * CLOUD_RIM_STRENGTH * strength);
    #endif
}
#endif
// Grid traversal for Java cloud geometry: light transmission through the cloud cells along the view and the light,
// aware of neighbouring cells. Java cells are 12x4x12 blocks.
#if CLOUD_RIM_STYLE == 1 || CLOUD_MODEL == 1
float shiroiCloudExit(vec3 origin, vec3 direction, float layerBottom) {
    const float limit = 12.0;
    float y = clamp(origin.y - layerBottom, 0.0, CLOUD_THICKNESS);
    float exitDistance = limit;
    if (direction.y > 0.00001)
        exitDistance = min(exitDistance, (CLOUD_THICKNESS - y) / direction.y);
    else if (direction.y < -0.00001)
        exitDistance = min(exitDistance, -y / direction.y);

    vec2 grid = cloudGridPos(origin.xz) / CLOUD_CELL;
    ivec2 cell = ivec2(floor(grid));
    vec2 local = fract(grid) * CLOUD_CELL;
    ivec2 stepCell = ivec2(sign(direction.xz));
    vec2 invDirection = 1.0 / max(abs(direction.xz), vec2(0.000001));
    vec2 nextBoundary = mix(local, vec2(CLOUD_CELL) - local,
                            greaterThan(direction.xz, vec2(0.0))) * invDirection;
    // Parallel axes must never cause a spurious crossing at an exact grid line.
    if (abs(direction.x) < 0.00001) nextBoundary.x = limit + 1.0;
    if (abs(direction.z) < 0.00001) nextBoundary.y = limit + 1.0;
    vec2 cellStep = CLOUD_CELL * invDirection;
    // A normalized ray shorter than one cell can cross at most two grid lines.
    // Four iterations include corner ties and floating-point boundary cases.
    for (int i = 0; i < 4; ++i) {
        float crossing = min(nextBoundary.x, nextBoundary.y);
        if (crossing >= exitDistance) break;
        bvec2 crossed = lessThanEqual(nextBoundary, vec2(crossing + 0.00001));
        if (crossed.x) { cell.x += stepCell.x; nextBoundary.x += cellStep.x; }
        if (crossed.y) { cell.y += stepCell.y; nextBoundary.y += cellStep.y; }
        if (!cloudCell(cell)) return max(crossing, 0.0);
    }
    return max(exitDistance, 0.0);
}

vec3 shiroiCloudTransmission(float viewDistance, float lightDistance,
                             float phase, float backDiffuse, vec3 albedo) {
    float thin = 1.0 - smoothstep(0.0, 8.0, viewDistance);
    float scattering = phase * exp(-lightDistance * CLOUD_DENSITY)
                     * (1.0 - smoothstep(0.0, 8.0, viewDistance * 0.5));
    return vec3(scattering) + albedo * (backDiffuse * INV_PI * thin);
}
#endif

#if CLOUD_RIM_STYLE == 1 && defined CLOUD_LIGHTING && !defined DIM_NETHER && !defined DIM_END
vec3 shiroiCloudBodyTransmission(vec3 worldPos, vec3 normal, vec3 viewRay,
                                float layerBottom, Celestial source, vec3 albedo) {
    float sourceFade = smoothstep(-0.08, 0.12, source.dir.y);
    float weather = (1.0 - saturate(rainStrength)) * (1.0 - saturate(thunderStrength));
    if (sourceFade * weather <= 0.0 || source.lux <= 0.0 || !cloudGridKnown()) return vec3(0.0);
    if (any(lessThanEqual(textureSize(cloudTex, 0), ivec2(0)))) return vec3(0.0);

    vec3 origin = worldPos - normal * 0.02;
    float y = clamp(origin.y - layerBottom, 0.0, CLOUD_THICKNESS);
    float slabView = 12.0;
    if (viewRay.y > 0.0001) slabView = min(slabView, (CLOUD_THICKNESS - y) / viewRay.y);
    else if (viewRay.y < -0.0001) slabView = min(slabView, -y / viewRay.y);
    float slabMidY = clamp(y + viewRay.y * slabView * 0.5, 0.0, CLOUD_THICKNESS);
    float slabLight = source.dir.y > 0.0001
        ? min((CLOUD_THICKNESS - slabMidY) / source.dir.y, 12.0) : 12.0;

    float viewDistance = shiroiCloudExit(origin, viewRay, layerBottom);
    vec3 midpoint = origin + viewRay * (viewDistance * 0.5);
    float lightDistance = shiroiCloudExit(midpoint, source.dir, layerBottom);
    float g = CLOUD_PHASE_G;
    float denominator = max(1.0 + g * g - 2.0 * g * dot(source.dir, viewRay), 0.001);
    float phase = (1.0 - g * g) * INV_4PI / (denominator * sqrt(denominator));
    float backDiffuse = max(dot(-normal, source.dir) + DIFFUSE_WRAP, 0.0)
                      / ((1.0 + DIFFUSE_WRAP) * (1.0 + DIFFUSE_WRAP));
    vec3 refined = shiroiCloudTransmission(viewDistance, lightDistance, phase, backDiffuse, albedo);
    vec3 slab = shiroiCloudTransmission(slabView, slabLight, phase, backDiffuse, albedo);
    // Correct the transmission missed by the infinite-slab model.
    // Orientation, optical thickness and adjacency determine where it is visible.
    return (refined - slab) * source.tint * source.lux
         * (sourceFade * weather * CLOUD_RIM_STRENGTH);
}
#endif

vec3 shiroiCloudSolarRim(vec3 worldPos, vec3 normal, vec3 viewRay,
                       float layerBottom, Daylight light, vec3 albedo, vec3 cloudColor) {
#if CLOUD_RIM_STYLE == 0
    return shiroiCloudClassicRim(worldPos, normal, viewRay, layerBottom, light);
#elif defined DIM_NETHER || defined DIM_END || !defined CLOUD_LIGHTING
    return vec3(0.0);
#else
    // Keep the approved daytime calculation, including its dusk fade.
    vec3 transmission = shiroiCloudBodyTransmission(worldPos, normal, viewRay,
                                                   layerBottom, light.sun, albedo);
    // Match the existing directional-light selection in daylight.glsl. The lunar
    // contribution retains the moon's own low illuminance and cool colour;
    // the phase ramp makes this extra term zero at the light-switch boundary.
    float d = sunPhase();
    if (d >= 0.25 && d <= 0.75) {
        float nightBlend = smoothstep(0.25, 0.27, d) * (1.0 - smoothstep(0.73, 0.75, d));
        // The renderer modulates diffuse transmission by the cloud's vertex
        // colour; scattering is a separate term. Preserve that distinction:
        // use the game-supplied face/day/weather tint only for the lunar diffuse
        // correction, without scaling the directional scattering lobe.
        vec3 lunarAlbedo = albedo * saturate(cloudColor);
        transmission += nightBlend * shiroiCloudBodyTransmission(worldPos, normal, viewRay,
                                                               layerBottom, light.moon, lunarAlbedo);
    }
    return transmission;
#endif
}

#endif
#endif
