//
//  NDIShaders.metal
//  NDIKitMetal
//
//  Compute kernels for converting between NDI wire formats and Metal textures.
//  All kernel names are prefixed with `ndi_` to avoid collisions with client shaders.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Types

/// Parameters passed from Swift to all conversion compute kernels.
/// Must match the layout of `NDIConversionParams` in Swift exactly.
struct NDIConversionParams {
    uint width;
    uint height;
    uint bytesPerRow;
    uint uvPlaneOffset;
    uint flags;
};

// MARK: - Color Math Helpers

/// BT.601 video-range YUV → RGB (8-bit UYVY decode).
inline float3 yuvToRgb601(float y, float u, float v) {
    float c = y - 16.0;
    float d = u - 128.0;
    float e = v - 128.0;

    float r = (298.0 * c + 409.0 * e + 128.0) / 256.0;
    float g = (298.0 * c - 100.0 * d - 208.0 * e + 128.0) / 256.0;
    float b = (298.0 * c + 516.0 * d + 128.0) / 256.0;

    return clamp(float3(r, g, b) / 255.0, 0.0, 1.0);
}

/// BT.709 video-range 16-bit YUV → RGB (P216 decode).
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

/// BT.709 full-range RGB → YUV (encode to UYVY wire format).
/// Input RGB is assumed to be in gamma-encoded sRGB / Rec.709.
/// Output Y is [16, 235], Cb/Cr is [16, 240] (video-range).
inline float3 rgbToYuv709(float3 rgb) {
    float y  =  16.0 + 65.481 * rgb.r + 128.553 * rgb.g +  24.966 * rgb.b;
    float cb = 128.0 - 37.797 * rgb.r -  74.203 * rgb.g + 112.0   * rgb.b;
    float cr = 128.0 + 112.0  * rgb.r -  93.786 * rgb.g -  18.214 * rgb.b;
    return float3(clamp(y, 16.0, 235.0), clamp(cb, 16.0, 240.0), clamp(cr, 16.0, 240.0));
}

/// Display P3 linear → sRGB/BT.709 linear gamut mapping (3×3 matrix).
inline float3 displayP3ToSrgb(float3 p3) {
    // Matrix derived from the P3-D65 → sRGB/BT.709 chromaticity adaptation.
    return float3(
        dot(p3, float3( 1.2249, -0.2247,  0.0)),
        dot(p3, float3(-0.0420,  1.0419,  0.0)),
        dot(p3, float3(-0.0197, -0.0786,  1.0979))
    );
}

/// Linear → sRGB gamma (OETF).
inline float linearToGamma(float x) {
    if (x <= 0.0031308) {
        return x * 12.92;
    }
    return 1.055 * pow(x, 1.0 / 2.4) - 0.055;
}

/// Linear → sRGB gamma for a float3.
inline float3 linearToGamma3(float3 v) {
    return float3(linearToGamma(v.r), linearToGamma(v.g), linearToGamma(v.b));
}

// MARK: - Decode Kernels (NDI Wire Buffer → BGRA Texture)

/// Decodes an 8-bit BGRA or BGRX buffer to a BGRA half4 texture.
/// 1 thread per pixel.
kernel void ndi_bgra_to_bgra(const device uchar *src [[buffer(0)]],
                             texture2d<half, access::write> dst [[texture(0)]],
                             constant NDIConversionParams &params [[buffer(1)]],
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

/// Decodes an 8-bit RGBA or RGBX buffer to a BGRA half4 texture.
/// 1 thread per pixel.
kernel void ndi_rgba_to_bgra(const device uchar *src [[buffer(0)]],
                             texture2d<half, access::write> dst [[texture(0)]],
                             constant NDIConversionParams &params [[buffer(1)]],
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

/// Decodes an 8-bit UYVY 4:2:2 buffer to a BGRA half4 texture using BT.601 coefficients.
/// 1 thread per pixel.
kernel void ndi_uyvy_to_bgra(const device uchar *src [[buffer(0)]],
                             texture2d<half, access::write> dst [[texture(0)]],
                             constant NDIConversionParams &params [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= params.width || gid.y >= params.height) {
        return;
    }

    uint pair = gid.x & ~1u;
    uint offset = gid.y * params.bytesPerRow + pair * 2;

    uchar u  = src[offset + 0];
    uchar y0 = src[offset + 1];
    uchar v  = src[offset + 2];
    uchar y1 = src[offset + 3];

    float y = (gid.x & 1u) == 0 ? float(y0) : float(y1);
    float3 rgb = yuvToRgb601(y, float(u), float(v));
    dst.write(half4(float4(rgb, 1.0)), gid);
}

/// Decodes a 16-bit P216 4:2:2 planar buffer to a BGRA half4 texture using BT.709 coefficients.
/// 1 thread per pixel.
kernel void ndi_p216_to_bgra(const device ushort *src [[buffer(0)]],
                             texture2d<half, access::write> dst [[texture(0)]],
                             constant NDIConversionParams &params [[buffer(1)]],
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

// MARK: - Encode Kernels (Metal Texture → NDI UYVY Wire Buffer)

/// Encodes NV12 bi-planar textures (r8Unorm luma + rg8Unorm chroma) to a UYVY packed buffer.
/// BT.709 full-range. 1 thread per 2-pixel macro-pixel.
kernel void ndi_nv12_to_uyvy(texture2d<float, access::read> luma [[texture(0)]],
                             texture2d<float, access::read> chroma [[texture(1)]],
                             device uchar *dst [[buffer(0)]],
                             constant NDIConversionParams &params [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    uint px = gid.x * 2;
    if (px >= params.width || gid.y >= params.height) {
        return;
    }

    // Read luma for both pixels in the macro-pixel.
    float y0 = luma.read(uint2(px, gid.y)).r;
    float y1 = (px + 1 < params.width) ? luma.read(uint2(px + 1, gid.y)).r : y0;

    // Read shared chroma (NV12: half width, half height).
    uint2 chromaCoord = uint2(gid.x, gid.y >> 1);
    float2 cbcr = chroma.read(chromaCoord).rg;

    // Write UYVY macro-pixel: U0 Y0 V0 Y1.
    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    dst[offset + 0] = uchar(cbcr.r * 255.0);  // U (Cb)
    dst[offset + 1] = uchar(y0 * 255.0);       // Y0
    dst[offset + 2] = uchar(cbcr.g * 255.0);   // V (Cr)
    dst[offset + 3] = uchar(y1 * 255.0);       // Y1
}

/// Encodes an 8-bit BGRA texture (.bgra8Unorm, sRGB/Rec.709) to a UYVY packed buffer.
/// RGB → YUV using BT.709 video-range coefficients. 1 thread per 2-pixel macro-pixel.
kernel void ndi_bgra_to_uyvy(texture2d<half, access::read> src [[texture(0)]],
                             device uchar *dst [[buffer(0)]],
                             constant NDIConversionParams &params [[buffer(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    uint px = gid.x * 2;
    if (px >= params.width || gid.y >= params.height) {
        return;
    }

    // Read two pixels from the source texture.
    half4 pixel0 = src.read(uint2(px, gid.y));
    half4 pixel1 = (px + 1 < params.width) ? src.read(uint2(px + 1, gid.y)) : pixel0;

    // The texture is .bgra8Unorm — Metal already swizzles to RGBA on read,
    // so .rgb gives us (R, G, B) in linear or gamma space depending on the
    // texture's pixel format. For sRGB textures, Metal returns linear values;
    // for non-sRGB .bgra8Unorm, values are already gamma-encoded.
    float3 rgb0 = float3(pixel0.rgb);
    float3 rgb1 = float3(pixel1.rgb);

    float3 yuv0 = rgbToYuv709(rgb0);
    float3 yuv1 = rgbToYuv709(rgb1);

    // Average the chroma of both pixels for the macro-pixel.
    float u = (yuv0.y + yuv1.y) * 0.5;
    float v = (yuv0.z + yuv1.z) * 0.5;

    // Write UYVY macro-pixel: U Y0 V Y1.
    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    dst[offset + 0] = uchar(clamp(u, 0.0, 255.0));
    dst[offset + 1] = uchar(clamp(yuv0.x, 0.0, 255.0));
    dst[offset + 2] = uchar(clamp(v, 0.0, 255.0));
    dst[offset + 3] = uchar(clamp(yuv1.x, 0.0, 255.0));
}

/// Encodes a 16-bit float RGBA texture (.rgba16Float, Display P3) to a UYVY packed buffer.
/// Display P3 → BT.709 gamut conversion, linear → gamma, RGB → YUV BT.709 video-range.
/// 1 thread per 2-pixel macro-pixel.
kernel void ndi_rgbaf_to_uyvy(texture2d<float, access::read> src [[texture(0)]],
                              device uchar *dst [[buffer(0)]],
                              constant NDIConversionParams &params [[buffer(1)]],
                              uint2 gid [[thread_position_in_grid]]) {
    uint px = gid.x * 2;
    if (px >= params.width || gid.y >= params.height) {
        return;
    }

    // Read two pixels in Display P3 linear.
    float4 pixel0 = src.read(uint2(px, gid.y));
    float4 pixel1 = (px + 1 < params.width) ? src.read(uint2(px + 1, gid.y)) : pixel0;

    // P3 linear → sRGB/BT.709 linear → gamma-encoded.
    float3 rgb0 = linearToGamma3(clamp(displayP3ToSrgb(pixel0.rgb), 0.0, 1.0));
    float3 rgb1 = linearToGamma3(clamp(displayP3ToSrgb(pixel1.rgb), 0.0, 1.0));

    float3 yuv0 = rgbToYuv709(rgb0);
    float3 yuv1 = rgbToYuv709(rgb1);

    // Average the chroma of both pixels for the macro-pixel.
    float u = (yuv0.y + yuv1.y) * 0.5;
    float v = (yuv0.z + yuv1.z) * 0.5;

    // Write UYVY macro-pixel: U Y0 V Y1.
    uint offset = gid.y * params.bytesPerRow + gid.x * 4;
    dst[offset + 0] = uchar(clamp(u, 0.0, 255.0));
    dst[offset + 1] = uchar(clamp(yuv0.x, 0.0, 255.0));
    dst[offset + 2] = uchar(clamp(v, 0.0, 255.0));
    dst[offset + 3] = uchar(clamp(yuv1.x, 0.0, 255.0));
}
