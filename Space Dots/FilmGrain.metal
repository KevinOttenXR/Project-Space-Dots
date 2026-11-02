#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

float hash21(float2 point) {
    point = fract(point * float2(123.34, 345.45));
    point += dot(point, point + 34.345);
    return fract(point.x * point.y);
}

/// Fine, flat film grain computed entirely on the GPU.
///
/// This is deliberately applied after the complete panel has been composited,
/// including its blur. It is not attached to, or masked by, the ribbons.
[[ stitchable ]] half4 filmGrain(
    float2 position,
    half4 color,
    float time,
    float intensity
) {
    const float frame = floor(time * 12.0);
    const float noise = hash21(
        floor(position * 0.75) + float2(frame * 17.0, frame * 29.0)
    );
    const float3 source = float3(color.rgb);
    const float grainMask = smoothstep(0.28, 0.82, noise);
    // Light-only variation keeps the red base rich instead of making it dull.
    // It is intentionally present over black as a subtle, flat film layer.
    const float grainAmount = grainMask * intensity * 0.22;
    const float3 result = min(source + float3(grainAmount), float3(1.0));
    return half4(half3(result), color.a);
}
