#include <metal_stdlib>
using namespace metal;

struct CreekVertex {
    float2 position;
    float4 color;
    float depth;
    float current;
};

struct RasterData {
    float4 position [[position]];
    float4 color;
    float2 world;
    float depth;
    float current;
};

vertex RasterData creekVertex(
    const device CreekVertex *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]]
) {
    CreekVertex input = vertices[vertexID];
    RasterData output;
    output.position = float4(input.position, 0, 1);
    output.color = input.color;
    output.world = input.position;
    output.depth = input.depth;
    output.current = input.current;
    return output;
}

fragment float4 creekFragment(
    RasterData input [[stage_in]],
    constant float &time [[buffer(0)]]
) {
    float4 color = input.color;
    if (input.depth > 0.0) {
        // Shape the Bend (5): authoritative depth controls body tone while
        // authoritative transfer independently controls ripple speed/contrast.
        // Wall time contributes phase only and never simulation authority.
        float depthTone = clamp(input.depth, 0.0, 1.0);
        float current = clamp(input.current, 0.0, 1.5);
        float ripple = sin(input.world.x * 34.0 - time * (0.7 + current * 3.2))
            * cos(input.world.y * 27.0 + time * (0.35 + current * 1.4));
        float glint = smoothstep(0.58, 0.96, ripple)
            * mix(0.025, 0.15, clamp(current, 0.0, 1.0));
        float depthShade = mix(0.045, -0.055, depthTone);
        color.rgb += depthShade + glint;
    }
    return color;
}
