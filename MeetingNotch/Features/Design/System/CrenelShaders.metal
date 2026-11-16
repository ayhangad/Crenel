#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Crenel's shader vocabulary: SwiftUI stitchable colour effects.

namespace crenel {
    // Ordered 4×4 Bayer threshold in 0…1.
    float bayer4(float2 cell) {
        const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
        int x = int(fmod(cell.x, 4.0));
        int y = int(fmod(cell.y, 4.0));
        return (m[y * 4 + x] + 0.5) / 16.0;
    }
}

/// Content resolving pixel by pixel. At `progress` 0 nothing is visible, at 1 everything.
/// Each `cell`-sized block switches on when the progress passes its Bayer threshold, so a
/// swap reads as an ordered dither rather than a fade.
[[ stitchable ]] half4 crenelDither(float2 position, half4 color, float progress, float cell) {
    float2 block = floor(position / cell);
    float threshold = crenel::bayer4(block);
    float visible = step(threshold, progress);
    return color * half(visible);
}

/// Light travelling along an edge. Draw the stroke of a shape in white and apply this:
/// a bright head circles the shape's centre with a fading tail. `speed` is turns per
/// second; `level` (0…1) widens and brightens the head (voice, activity).
[[ stitchable ]] half4 crenelBeam(float2 position, half4 color, float2 size, float time,
                                  half4 tint, float speed, float level) {
    float2 center = size * 0.5;
    float2 d = (position - center) / max(size, float2(1.0));
    float angle = atan2(d.y, d.x) / (2.0 * M_PI_F) + 0.5;     // 0…1 around the shape
    float head = fract(time * speed);
    float behind = fract(head - angle);                       // 0 at the head, grows along the tail
    float length = 0.18 + level * 0.22;
    float tail = smoothstep(length, 0.0, behind);
    float glow = pow(tail, 1.8) * (0.75 + 0.25 * level) + 0.14;
    return half4(tint.rgb * half(glow), half(glow)) * color.a;
}
