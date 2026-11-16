#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Crenel's shader vocabulary. Every effect is a SwiftUI stitchable `colorEffect` or
// `layerEffect`, driven by a TimelineView clock and a few parameters.

namespace crenel {
    float hash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float noise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
                   mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }

    float fbm(float2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        for (int i = 0; i < 4; i++) {
            value += amplitude * noise(p);
            p *= 2.03;
            amplitude *= 0.5;
        }
        return value;
    }
}

/// A slowly turning sphere of dots. `level` (0…1) swells the dots with the voice; the
/// sphere's colour runs from `top` to `bottom`. Used for dictation, recording and the
/// onboarding hero.
[[ stitchable ]] half4 crenelDotOrb(float2 position, half4 color, float2 size, float time,
                                    half4 top, half4 bottom, float level, float density) {
    float2 center = size * 0.5;
    float radius = min(size.x, size.y) * 0.42 * (1.0 + level * 0.06);
    float2 uv = (position - center) / radius;
    float r2 = dot(uv, uv);

    // Soft halo outside the sphere.
    float halo = exp(-max(0.0, sqrt(r2) - 1.0) * 5.0) * (0.22 + level * 0.35);
    half3 haloColor = mix(top.rgb, bottom.rgb, half(0.65));
    if (r2 > 1.0) {
        return half4(haloColor * half(halo), half(halo));
    }

    float z = sqrt(1.0 - r2);
    float3 p = float3(uv.x, uv.y, z);
    // Rotate around Y with time and a slight tilt around X.
    float a = time * 0.35;
    float3 q = float3(p.x * cos(a) + p.z * sin(a), p.y, -p.x * sin(a) + p.z * cos(a));
    float tilt = 0.32;
    q = float3(q.x, q.y * cos(tilt) - q.z * sin(tilt), q.y * sin(tilt) + q.z * cos(tilt));

    float latitude = asin(clamp(q.y, -1.0, 1.0));
    float longitude = atan2(q.x, q.z);
    float rows = density;
    float row = floor((latitude / M_PI_F + 0.5) * rows);
    float rowLatitude = ((row + 0.5) / rows - 0.5) * M_PI_F;
    float columns = max(3.0, floor(rows * 2.0 * cos(rowLatitude)));
    float column = floor((longitude / (2.0 * M_PI_F) + 0.5) * columns);
    float cellLongitude = ((column + 0.5) / columns - 0.5) * 2.0 * M_PI_F;
    float3 cell = float3(cos(rowLatitude) * sin(cellLongitude), sin(rowLatitude), cos(rowLatitude) * cos(cellLongitude));
    float distanceToCell = length(q - cell);

    // Dots breathe individually and with the voice level.
    float jitter = crenel::hash(float2(row, column));
    float pulse = 0.5 + 0.5 * sin(time * 2.2 + jitter * 6.283);
    float dotRadius = (0.55 + 0.25 * pulse * level + level * 0.35) * (M_PI_F / rows) * 0.42;
    float dotMask = smoothstep(dotRadius, dotRadius * 0.55, distanceToCell);

    // Front-facing dots are brighter; the rim fades out.
    float facing = smoothstep(0.0, 0.6, z);
    half3 tint = mix(top.rgb, bottom.rgb, half(smoothstep(-0.55, 0.65, -uv.y)));
    half3 glow = haloColor * half(halo * 0.6);
    half alpha = half(dotMask * (0.25 + 0.75 * facing));
    return half4(tint * alpha + glow, max(alpha, half(halo * 0.6)));
}

/// A living ambient light: soft noise-driven colour pools drifting under content. Used
/// behind hero cards so surfaces feel lit, not flat.
[[ stitchable ]] half4 crenelAura(float2 position, half4 color, float2 size, float time,
                                  half4 tint, float intensity) {
    float2 uv = position / max(size.x, size.y);
    float n = crenel::fbm(uv * 2.4 + float2(time * 0.05, -time * 0.035));
    float m = crenel::fbm(uv * 3.1 - float2(time * 0.03, time * 0.045) + 7.1);
    float2 focus = float2(0.18 + 0.08 * sin(time * 0.2), 0.0 + 0.05 * cos(time * 0.17));
    float falloff = exp(-length((position / size) - focus) * 2.2);
    float value = (n * 0.6 + m * 0.4) * falloff * intensity;
    return half4(tint.rgb * half(value), half(value));
}

/// A highlight band sweeping across text or a glyph, keeping its alpha. Marks work in
/// progress (transcribing, summarizing) without a spinner.
[[ stitchable ]] half4 crenelShimmer(float2 position, half4 color, float2 size, float time,
                                     float strength) {
    float band = fract(time * 0.45) * (size.x + 160.0) - 80.0;
    float d = abs(position.x - band - position.y * 0.35);
    float highlight = smoothstep(46.0, 0.0, d) * strength;
    half3 lifted = mix(color.rgb, half3(color.a), half(highlight));
    return half4(lifted, color.a);
}

/// Edge glow tracing the inside of the notch while it listens or records.
[[ stitchable ]] half4 crenelEdgeGlow(float2 position, half4 color, float2 size, float time,
                                      half4 tint, float level) {
    float2 d = min(position, size - position);
    float edge = min(d.x, d.y * 1.6);
    float wave = 0.5 + 0.5 * sin(position.x * 0.035 - time * 3.0);
    float glow = exp(-edge / (6.0 + level * 10.0)) * (0.35 + 0.65 * wave) * (0.4 + level);
    return half4(tint.rgb * half(glow), half(glow) * tint.a);
}
