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
    if (input.water > 0.0) {
        float ripple = sin(input.world.x * 34.0 - time * 2.4)
            * cos(input.world.y * 27.0 + time * 1.2);
        float glint = smoothstep(0.62, 0.96, ripple)
            * mix(0.13, 0.055, input.water);
        float edgeLight = 0.035 * (1.0 - input.water);
        color.rgb += glint + edgeLight;
    }
    return color;
}
