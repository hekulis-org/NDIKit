#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

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

fragment half4 passthroughFragment(VertexOut in [[stage_in]],
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
    uint uvPlaneOffset;
    uint flags;
};

inline float3 yuvToRgb601(float y, float u, float v) {
    float c = y - 16.0;
    float d = u - 128.0;
    float e = v - 128.0;

    float r = (298.0 * c + 409.0 * e + 128.0) / 256.0;
    float g = (298.0 * c - 100.0 * d - 208.0 * e + 128.0) / 256.0;
    float b = (298.0 * c + 516.0 * d + 128.0) / 256.0;

    return clamp(float3(r, g, b) / 255.0, 0.0, 1.0);
}

inline float3 yuvToRgb709_16(float y, float u, float v) {
    float yScaled = y - 4096.0;
    float uScaled = u - 32768.0;
    float vScaled = v - 32768.0;

    float yNorm = yScaled / 56064.0;
    float uNorm = uScaled / 32768.0;
    float vNorm = vScaled / 32768.0;

    float r = yNorm + 1.5748 * vNorm;
    float g = yNorm - 0.1873 * uNorm - 0.4681 * vNorm;
    float b = yNorm + 1.8556 * uNorm;

    return clamp(float3(r, g, b), 0.0, 1.0);
}

kernel void bgra_to_bgra(const device uchar *src [[buffer(0)]],
                         texture2d<half, access::write> dst [[texture(0)]],
                         constant ConversionParams &params [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    uchar b = src[offset + 0];
    uchar g = src[offset + 1];
    uchar r = src[offset + 2];
    uchar a = (params.flags & 1u) != 0 ? src[offset + 3] : 255;

    float4 color = float4(float(r), float(g), float(b), float(a)) / 255.0;
    dst.write(half4(color), gid);
}

kernel void rgba_to_bgra(const device uchar *src [[buffer(0)]],
                         texture2d<half, access::write> dst [[texture(0)]],
                         constant ConversionParams &params [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    uchar r = src[offset + 0];
    uchar g = src[offset + 1];
    uchar b = src[offset + 2];
    uchar a = (params.flags & 1u) != 0 ? src[offset + 3] : 255;

    float4 color = float4(float(r), float(g), float(b), float(a)) / 255.0;
    dst.write(half4(color), gid);
}

kernel void uyvy_to_bgra(const device uchar *src [[buffer(0)]],
                         texture2d<half, access::write> dst [[texture(0)]],
                         constant ConversionParams &params [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint pair = gid.x & ~1u;
    uint offset = gid.y * params.bytesPerRow + pair * 2;

    uchar u = src[offset + 0];
    uchar y0 = src[offset + 1];
    uchar v = src[offset + 2];
    uchar y1 = src[offset + 3];

    float y = (gid.x & 1u) == 0 ? float(y0) : float(y1);
    float3 rgb = yuvToRgb601(y, float(u), float(v));
    dst.write(half4(float4(rgb, 1.0)), gid);
}

kernel void p216_to_bgra(const device ushort *src [[buffer(0)]],
                         texture2d<half, access::write> dst [[texture(0)]],
                         constant ConversionParams &params [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint stride = params.bytesPerRow / 2;
    uint yIndex = gid.y * stride + gid.x;
    uint uvBase = params.uvPlaneOffset / 2 + gid.y * stride;
    uint uvIndex = uvBase + (gid.x & ~1u);

    float y = float(src[yIndex]);
    float u = float(src[uvIndex]);
    float v = float(src[uvIndex + 1]);

    float3 rgb = yuvToRgb709_16(y, u, v);
    dst.write(half4(float4(rgb, 1.0)), gid);
}
