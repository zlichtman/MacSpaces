#include <metal_stdlib>
using namespace metal;

// Bounded to 3 pt horizontally and 2 pt vertically. Side blooms sway, roots stay
// planted, and the center sky stays calm. Lotus also has a restrained water ripple.
[[ stitchable ]] float2 floralBreeze(float2 position, float2 size, float time, float lotus) {
    float2 uv = position / max(size, float2(1.0));
    float sides = smoothstep(0.10, 0.43, abs(uv.x - 0.5));
    float stem = pow(1.0 - clamp(uv.y, 0.0, 1.0), 1.25);
    float breeze = sin(time * 0.55 + uv.x * 5.0) * 0.72
                 + sin(time * 0.29 - uv.y * 3.0) * 0.28;
    float dx = 2.8 * sides * stem * breeze;
    float dy = 0.8 * sides * stem * sin(time * 0.41 + uv.x * 4.0);
    dy += lotus * smoothstep(0.62, 1.0, uv.y) * sin(uv.y * 45.0 - time * 0.7) * 0.7;
    return position + float2(dx, dy);
}
