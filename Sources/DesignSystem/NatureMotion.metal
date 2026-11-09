#include <metal_stdlib>
using namespace metal;

// Most scenes stay within 3 x 2 pt; Aurora uses 6 x 12 pt with larger overscan.
// The UI is drawn above this layer.
[[ stitchable ]] float2 natureMotion(float2 position, float2 size, float time, float kind) {
    float2 uv = position / max(size, float2(1.0));
    float2 offset = float2(0.0);
    if (kind < 0.5) {
        // Dune: fine wind ripples across the foreground, keeping the skyline steady.
        float sand = smoothstep(0.52, 0.94, uv.y);
        offset.x = sand * 0.9 * sin(uv.y * 70.0 - time * 1.0);
        offset.y = sand * 0.3 * sin(uv.x * 28.0 + time * 0.7);
    } else if (kind < 1.5) {
        float heat = smoothstep(0.25, 0.9, uv.y);
        offset.x = heat * 1.5 * sin(uv.y * 18.0 - time * 1.2);
        offset.y = heat * 0.7 * cos(uv.x * 15.0 + time * 0.65);
    } else if (kind < 2.5) {
        float water = smoothstep(0.28, 0.8, uv.y);
        offset.x = water * 2.1 * sin(uv.y * 22.0 - time * 0.75);
        offset.y = water * 1.2 * sin(uv.x * 16.0 + uv.y * 8.0 - time * 0.6);
    } else if (kind < 3.5) {
        offset.x = smoothstep(0.4, 0.9, uv.y) * 0.4 * sin(uv.y * 25.0 - time * 0.6);
    } else if (kind > 5.5 && kind < 6.5) {
        float sky = 1.0 - smoothstep(0.6, 0.86, uv.y);
        offset.x = sky * 6.0 * sin(time * 0.45 + uv.y * 7.0);
        offset.y = sky * 12.0 * sin(uv.x * 8.0 + time * 0.55);
    } else if (kind > 6.5) {
        float sides = smoothstep(0.05, 0.42, abs(uv.x - 0.5));
        offset.x = sides * 2.2 * sin(uv.y * 9.0 + time * 0.2);
        offset.y = sides * 1.5 * cos(uv.x * 8.0 - time * 0.16);
    } else {
        float sides = smoothstep(0.1, 0.44, abs(uv.x - 0.5));
        offset.x = sides * (1.0 - uv.y) * 1.8 * sin(time * 0.5 + uv.x * 4.0);
        offset.y = sides * 0.5 * sin(time * 0.4 + uv.y * 5.0);
    }
    return position + offset;
}
