#ifdef MOD_COMPAT
#ifndef MOD_COMPAT_GLSL
#define MOD_COMPAT_GLSL
// Invalid-data repair only: an unmapped id does not reveal its registry namespace.
#ifdef MOD_COMPAT
// Iris exposes DimensionType metadata. Vitrail does not promise these uniforms;
// heightLimit > 0 additionally protects against an unbound set on other engines.
#ifndef SHADOW_SINGLE_PASS
uniform bool hasSkylight;
uniform bool hasCeiling;
uniform int bedrockLevel;
uniform int heightLimit;
uniform vec3 fogColor;
#endif
bool mcCompatDimensionInfo() {
    #if !defined SHADOW_SINGLE_PASS && !defined DIM_NETHER && !defined DIM_END
        return heightLimit > 0;
    #else
        return false;
    #endif
}
bool mcCompatSkyless() {
    #if !defined SHADOW_SINGLE_PASS && !defined DIM_NETHER && !defined DIM_END
        return mcCompatDimensionInfo() && (hasCeiling || !hasSkylight);
    #else
        return false;
    #endif
}
float mcCompatWorldTop(float original) {
    #if !defined SHADOW_SINGLE_PASS && !defined DIM_NETHER && !defined DIM_END
        if (mcCompatDimensionInfo() && (bedrockLevel != -64 || heightLimit != 384))
            return float(bedrockLevel) + float(heightLimit);
    #endif
    return original;
}
vec3 mcCompatDimensionFog() {
    #ifndef SHADOW_SINGLE_PASS
        if (!any(isnan(fogColor)) && !any(isinf(fogColor)))
            return max(srgbToLinear(clamp(fogColor, 0.0, 1.0)), vec3(0.025));
    #endif
    return vec3(0.025);
}
#endif

bool mcCompatFinite(float x) { return !isnan(x) && !isinf(x); }
bool mcCompatNormalOK(vec3 n) {
    float n2 = dot(n, n);
    return !any(isnan(n)) && !any(isinf(n)) && n2 > 1e-12 && mcCompatFinite(n2);
}
vec2 mcCompatLightmap(vec2 lm) {
    return vec2(mcCompatFinite(lm.x) ? clamp(lm.x, 0.0, 1.0) : 0.0,
                mcCompatFinite(lm.y) ? clamp(lm.y, 0.0, 1.0) : 0.0);
}
vec3 mcCompatColor(vec3 c) {
    return vec3(mcCompatFinite(c.x) ? clamp(c.x, 0.0, 1.0) : 0.0,
                mcCompatFinite(c.y) ? clamp(c.y, 0.0, 1.0) : 0.0,
                mcCompatFinite(c.z) ? clamp(c.z, 0.0, 1.0) : 0.0);
}
#ifdef FRAGMENT_SHADER
// Evaluated before alpha discard. A missing vertex normal gets the actual triangle
// normal, not an up-vector that would flatten all model lighting.
vec3 mcCompatFaceNormal(vec3 p) {
    vec3 n = cross(dFdx(p), dFdy(p));
    if (!mcCompatNormalOK(n)) return vec3(0.0, 1.0, 0.0);
    n *= inversesqrt(dot(n, n));
    return dot(n, -p) < 0.0 ? -n : n;
}
#endif
#endif
#endif
