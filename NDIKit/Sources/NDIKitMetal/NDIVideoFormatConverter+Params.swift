//
//  NDIVideoFormatConverter+Params.swift
//  NDIKitMetal
//
//  Swift-side mirror of the Metal `NDIConversionParams` struct, with
//  convenience builders for decode and encode use cases.
//

import NDIKit

/// Parameters passed to NDIKitMetal conversion compute shaders.
///
/// This struct matches the Metal-side `NDIConversionParams` layout exactly
/// and is passed to the GPU via `setBytes(_:length:index:)`.
///
/// Use the static factory methods to build params for decode or encode:
///
/// ```swift
/// // Decode from an NDIVideoFrame:
/// var params = NDIConversionParams.decode(frame: frame)
///
/// // Encode to a UYVY buffer:
/// var params = NDIConversionParams.encode(width: 1920, height: 1080, uyvyBytesPerRow: 3840)
/// ```
public struct NDIConversionParams: Sendable {
    /// Frame width in pixels.
    public var width: UInt32
    /// Frame height in pixels.
    public var height: UInt32
    /// Bytes per row (line stride) of the source or destination buffer.
    public var bytesPerRow: UInt32
    /// Byte offset to the UV plane within the buffer (P216 decode only).
    public var uvPlaneOffset: UInt32
    /// Bit flags. Bit 0: source has a meaningful alpha channel.
    public var flags: UInt32

    /// Creates params with explicit values.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - bytesPerRow: Line stride in bytes.
    ///   - uvPlaneOffset: UV plane offset in bytes (0 for non-planar formats).
    ///   - flags: Bit flags (bit 0 = has alpha).
    public init(
        width: UInt32,
        height: UInt32,
        bytesPerRow: UInt32,
        uvPlaneOffset: UInt32 = 0,
        flags: UInt32 = 0
    ) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.uvPlaneOffset = uvPlaneOffset
        self.flags = flags
    }
}

// MARK: - Decode Builders

extension NDIConversionParams {

    /// Builds decode params from an ``NDIVideoFrame``.
    ///
    /// Automatically determines the UV plane offset (for P216) and alpha
    /// flag based on the frame's ``FourCC``.
    ///
    /// - Parameter frame: The NDI video frame to decode.
    /// - Returns: Params ready to pass to a decode compute shader.
    public static func decode(frame: NDIVideoFrame) -> NDIConversionParams {
        decode(
            width: frame.width,
            height: frame.height,
            bytesPerRow: frame.lineStride,
            fourCC: frame.fourCC,
            hasAlpha: frame.fourCC == .bgra || frame.fourCC == .rgba
        )
    }

    /// Builds decode params from raw values.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - bytesPerRow: Line stride in bytes.
    ///   - fourCC: The pixel format of the source buffer.
    ///   - hasAlpha: Whether the source has a meaningful alpha channel.
    /// - Returns: Params ready to pass to a decode compute shader.
    public static func decode(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        fourCC: FourCC,
        hasAlpha: Bool
    ) -> NDIConversionParams {
        let uvPlaneOffset: UInt32 = fourCC == .p216
            ? UInt32(bytesPerRow * height)
            : 0

        return NDIConversionParams(
            width: UInt32(width),
            height: UInt32(height),
            bytesPerRow: UInt32(bytesPerRow),
            uvPlaneOffset: uvPlaneOffset,
            flags: hasAlpha ? 1 : 0
        )
    }
}

// MARK: - Encode Builders

extension NDIConversionParams {

    /// Builds encode params for writing to a UYVY buffer.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - uyvyBytesPerRow: Line stride of the destination UYVY buffer in bytes.
    /// - Returns: Params ready to pass to an encode compute shader.
    public static func encode(
        width: Int,
        height: Int,
        uyvyBytesPerRow: Int
    ) -> NDIConversionParams {
        NDIConversionParams(
            width: UInt32(width),
            height: UInt32(height),
            bytesPerRow: UInt32(uyvyBytesPerRow)
        )
    }
}

// MARK: - Buffer Size Helpers

extension NDIConversionParams {

    /// Computes the byte length needed for an NDI frame buffer.
    ///
    /// For P216 (planar 4:2:2), the buffer contains both Y and UV planes,
    /// so the total size is `lineStride × height × 2`. For all other
    /// formats the size is `lineStride × height`.
    ///
    /// - Parameters:
    ///   - bytesPerRow: Line stride in bytes.
    ///   - height: Frame height in pixels.
    ///   - fourCC: The pixel format of the buffer.
    /// - Returns: The total buffer size in bytes.
    public static func bufferLength(
        bytesPerRow: Int,
        height: Int,
        fourCC: FourCC
    ) -> Int {
        if fourCC == .p216 {
            return bytesPerRow * height * 2
        }
        return bytesPerRow * height
    }
}
