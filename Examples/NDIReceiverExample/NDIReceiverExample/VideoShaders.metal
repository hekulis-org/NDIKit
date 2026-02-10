#include <metal_stdlib>
using namespace metal;

/// Vertex output for the full-screen passthrough quad.
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// Full-screen quad vertex shader using a 4-vertex triangle strip.
vertex VertexOut passthroughVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    constexpr float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

/// Samples the converted BGRA texture and forces alpha to 1.
fragment half4 passthroughFragment(VertexOut in [[stage_in]],
                                   texture2d<half, access::sample> colorTexture [[texture(0)]],
                                   sampler samp [[sampler(0)]]) {
    half4 color = colorTexture.sample(samp, in.texCoord);
    color.a = half(1.0);
    return color;
}
