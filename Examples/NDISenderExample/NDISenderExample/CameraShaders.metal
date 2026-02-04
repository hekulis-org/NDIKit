#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut cameraVertex(uint vertexID [[vertex_id]]) {
    constexpr float4 positions[6] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0)
    };
    constexpr float2 texCoords[6] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0),
        float2(0.0, 0.0)
    };

    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment half4 cameraFragment(VertexOut in [[stage_in]],
                              texture2d<half, access::sample> colorTexture [[texture(0)]],
                              sampler samp [[sampler(0)]]) {
    half4 color = colorTexture.sample(samp, in.texCoord);
    color.a = half(1.0);
    return color;
}

struct ConversionParams {
    uint width;
    uint height;
    uint bytesPerRow;
};

// CoreVideo’s bi-planar 4:2:0 pixel buffers map directly to NV12
kernel void nv12_to_bgra(texture2d<float, access::read> luma [[texture(0)]],
                         texture2d<float, access::read> chroma [[texture(1)]],
                         device uchar *dst [[buffer(0)]],
                         constant ConversionParams &params [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    float y = luma.read(gid).r;
    uint2 chromaCoord = uint2(gid.x >> 1, gid.y >> 1);
    float2 uv = chroma.read(chromaCoord).rg - float2(0.5, 0.5);

    float r = y + 1.5748 * uv.y;
    float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
    float b = y + 1.8556 * uv.x;

    float3 rgb = clamp(float3(r, g, b), 0.0, 1.0);

    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    dst[offset + 0] = uchar(rgb.b * 255.0);
    dst[offset + 1] = uchar(rgb.g * 255.0);
    dst[offset + 2] = uchar(rgb.r * 255.0);
    dst[offset + 3] = 255;
}
