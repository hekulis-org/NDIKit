#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut cameraVertex(uint vertexID [[vertex_id]]) {
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

// Converts NV12 (4:2:0 bi-planar) to UYVY (4:2:2 packed) for NDI,
// and simultaneously writes BGRA to a display texture for on-screen preview.
// Each thread processes a macro-pixel (2 horizontal pixels).
kernel void nv12_to_uyvy(texture2d<float, access::read> luma [[texture(0)]],
                         texture2d<float, access::read> chroma [[texture(1)]],
                         texture2d<float, access::write> display [[texture(2)]],
                         device uchar *dst [[buffer(0)]],
                         constant ConversionParams &params [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    uint px = gid.x * 2;
    if (px >= params.width || gid.y >= params.height) {
        return;
    }

    // Read luma for both pixels in the macro-pixel
    float y0 = luma.read(uint2(px, gid.y)).r;
    float y1 = (px + 1 < params.width) ? luma.read(uint2(px + 1, gid.y)).r : y0;

    // Read shared chroma (NV12: half width, half height)
    uint2 chromaCoord = uint2(gid.x, gid.y >> 1);
    float2 cbcr = chroma.read(chromaCoord).rg;

    // Write UYVY macro-pixel: U0 Y0 V0 Y1
    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    dst[offset + 0] = uchar(cbcr.r * 255.0);  // U (Cb)
    dst[offset + 1] = uchar(y0 * 255.0);       // Y0
    dst[offset + 2] = uchar(cbcr.g * 255.0);   // V (Cr)
    dst[offset + 3] = uchar(y1 * 255.0);       // Y1

    // Convert to RGB for display (BT.709 full-range)
    float2 uv = cbcr - float2(0.5, 0.5);

    float r0 = y0 + 1.5748 * uv.y;
    float g0 = y0 - 0.1873 * uv.x - 0.4681 * uv.y;
    float b0 = y0 + 1.8556 * uv.x;
    display.write(float4(clamp(float3(r0, g0, b0), 0.0, 1.0), 1.0), uint2(px, gid.y));

    if (px + 1 < params.width) {
        float r1 = y1 + 1.5748 * uv.y;
        float g1 = y1 - 0.1873 * uv.x - 0.4681 * uv.y;
        float b1 = y1 + 1.8556 * uv.x;
        display.write(float4(clamp(float3(r1, g1, b1), 0.0, 1.0), 1.0), uint2(px + 1, gid.y));
    }
}
