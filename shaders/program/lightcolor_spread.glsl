// Coloured block light (lib/lightcolor.glsl): the splatted light colours spread over the grid with a separable Gaussian
// (sigma 2.5 cells = 5 blocks, 6 cells each side), one axis per pass:
//  LC_X  splat SSBO (written by the previous frame's terrain pass) -> lcA (converts the fixed point sums)
//  LC_Y  lcA -> lcB, and clears the splat for the next frame (the x pass has read it)
//  LC_Z  lcB, blended into the colours remembered from the earlier frames (moved with the camera's grid), -> lcC on
//        even frames, lcD on odd ones (read by the shading)
#include "/lib/common.glsl"
#define LC_SPLAT
#include "/lib/lightcolor.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
// Iris parses workGroups with Integer.parseInt per component: literals only (LC_GRID / 8)
const ivec3 workGroups = ivec3(8, 4, 8);

#ifdef LC_X
writeonly uniform image3D lcA;
#elif defined LC_Y
uniform sampler3D lcASampler;
writeonly uniform image3D lcB;
#else
uniform sampler3D lcBSampler;
uniform sampler3D lcCSampler;
uniform sampler3D lcDSampler;
writeonly uniform image3D lcC;
writeonly uniform image3D lcD;
#endif

vec4 lcRead(ivec3 c) {
    #ifdef LC_X
        // the terrain pass splats after the prepare passes, so the splat is the previous frame's, on its grid
        c += lcOrigin(cameraPosition) - lcOrigin(previousCameraPosition);
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, LC_GRID))) return vec4(0.0);
        int i = ((c.z * LC_GRID.y + c.y) * LC_GRID.x + c.x) * 4;
        return vec4(lcSplat[i], lcSplat[i + 1], lcSplat[i + 2], lcSplat[i + 3]) / 64.0;
    #elif defined LC_Y
        return texelFetch(lcASampler, c, 0);
    #else
        return texelFetch(lcBSampler, c, 0);
    #endif
}

void main() {
    ivec3 id = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(id, LC_GRID))) return;
    #if defined LC_X
        const ivec3 axis = ivec3(1, 0, 0);
    #elif defined LC_Y
        const ivec3 axis = ivec3(0, 1, 0);
    #else
        const ivec3 axis = ivec3(0, 0, 1);
    #endif
    vec4 sum = vec4(0.0);
    for (int k = -6; k <= 6; k++) {
        ivec3 c = id + axis * k;
        if (any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, LC_GRID))) continue;
        sum += lcRead(c) * exp(-float(k * k) / 12.5);
    }
    sum /= 6.2666;   // the kernel's total: the weight keeps its scale
    #if defined LC_X
        imageStore(lcA, id, sum);
    #elif defined LC_Y
        imageStore(lcB, id, sum);
        int i = ((id.z * LC_GRID.y + id.y) * LC_GRID.x + id.x) * 4;
        lcSplat[i] = 0u; lcSplat[i + 1] = 0u; lcSplat[i + 2] = 0u; lcSplat[i + 3] = 0u;
    #else
        // a cell that sees lights now follows them within a few frames; one that does not (lights behind the camera,
        // out of the terrain pass) keeps what it had, fading over ~3 s
        ivec3 prev = id + lcOrigin(cameraPosition) - lcOrigin(previousCameraPosition);
        vec4 old = vec4(0.0);
        if (all(greaterThanEqual(prev, ivec3(0))) && all(lessThan(prev, LC_GRID)))
            old = (frameCounter & 1) == 0 ? texelFetch(lcDSampler, prev, 0) : texelFetch(lcCSampler, prev, 0);
        vec4 v = sum.a > 1e-4 ? mix(old, sum, 0.25) : old * 0.995;
        if ((frameCounter & 1) == 0) imageStore(lcC, id, v);
        else imageStore(lcD, id, v);
    #endif
}
