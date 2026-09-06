#include <metal_stdlib>
using namespace metal;

struct CreekVertex {
    float2 position;
    float4 color;
    float water;
};

struct RasterData {
    float4 position [[position]];
    float4 color;
    float2 world;
    float water;
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
    output.water = input.water;
    return output;
}

fragment float4 creekFragment(
    RasterData input [[stage_in]],
    constant float &time [[buffer(0)]]
) {
    float4 color = input.color;
    if (input.water > 0.5) {
        float ripple = sin(input.world.x * 42.0 - time * 2.4)
            * cos(input.world.y * 31.0 + time * 1.2);
        float glint = smoothstep(0.55, 0.95, ripple) * 0.10;
        color.rgb += glint;
    }
    return color;
}
