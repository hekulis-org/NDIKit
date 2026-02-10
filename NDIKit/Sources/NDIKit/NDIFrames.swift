import NDIKitC
import Foundation

// MARK: - Video Frame

/// A video frame received from an NDI source.
///
/// The underlying pixel data is owned by the NDI SDK and remains valid
/// until ``free()`` is called or the frame is deallocated. Call
/// ``copyData()`` if you need the pixels to outlive the frame.
public final class NDIVideoFrame: @unchecked Sendable {
    private let receiver: NDIlib_recv_instance_t
    private var frame: NDIlib_video_frame_v2_t
    private var isFreed = false

    /// The frame width in pixels.
    public var width: Int { Int(frame.xres) }

    /// The frame height in pixels.
    public var height: Int { Int(frame.yres) }

    /// The pixel format of the frame, expressed as a ``FourCC`` code.
    public var fourCC: FourCC { FourCC(frame.FourCC) }

    /// The frame rate expressed as a fraction (numerator / denominator).
    ///
    /// For example, 29.97 fps is represented as `(30000, 1001)`.
    public var frameRate: (numerator: Int, denominator: Int) {
        (Int(frame.frame_rate_N), Int(frame.frame_rate_D))
    }

    /// The frame rate as a floating-point value in frames per second.
    public var frameRateValue: Double {
        Double(frame.frame_rate_N) / Double(frame.frame_rate_D)
    }

    /// The picture aspect ratio. A value of `0` indicates square pixels.
    public var aspectRatio: Float { frame.picture_aspect_ratio }

    /// The scan type of the frame (progressive or interlaced).
    public var formatType: FrameFormat { FrameFormat(frame.frame_format_type) }

    /// The timecode of the frame, in 100-nanosecond intervals.
    public var timecode: Int64 { frame.timecode }

    /// The timestamp when the frame was submitted by the sender, in
    /// 100-nanosecond intervals, or `nil` if not available.
    public var timestamp: Int64? {
        frame.timestamp == NDIlib_recv_timestamp_undefined ? nil : frame.timestamp
    }

    /// The number of bytes per row (line stride) in the pixel buffer.
    public var lineStride: Int { Int(frame.line_stride_in_bytes) }

    /// Per-frame metadata as an XML string, or `nil` if none was attached.
    public var metadata: String? {
        frame.p_metadata.map { String(cString: $0) }
    }

    /// Direct access to the frame's raw pixel data.
    ///
    /// - Warning: This pointer is only valid while the frame has not been
    ///   freed. Call ``copyData()`` if you need the data to persist.
    public var data: UnsafeBufferPointer<UInt8>? {
        guard !isFreed, let ptr = frame.p_data else { return nil }
        let size = lineStride * height
        return UnsafeBufferPointer(start: ptr, count: size)
    }

    /// Copies the frame's pixel data into a Foundation `Data` object.
    ///
    /// - Returns: A `Data` containing the pixel bytes, or `nil` if the
    ///   frame has already been freed.
    public func copyData() -> Data? {
        guard let buffer = data else { return nil }
        return Data(buffer)
    }

    init(receiver: NDIlib_recv_instance_t, frame: NDIlib_video_frame_v2_t) {
        self.receiver = receiver
        self.frame = frame
    }

    deinit {
        freeIfNeeded()
    }

    /// Releases the frame's pixel data back to the NDI SDK.
    ///
    /// This is called automatically when the frame is deallocated, but you
    /// may call it earlier to free memory sooner.
    public func free() {
        freeIfNeeded()
    }

    private func freeIfNeeded() {
        guard !isFreed else { return }
        isFreed = true
        NDIlib_recv_free_video_v2(receiver, &frame)
    }
}

// MARK: - Audio Frame

/// An audio frame received from an NDI source.
///
/// Audio samples are 32-bit float in planar layout. The underlying data
/// is owned by the NDI SDK and remains valid until ``free()`` is called
/// or the frame is deallocated.
public final class NDIAudioFrame: @unchecked Sendable {
    private let receiver: NDIlib_recv_instance_t
    private var frame: NDIlib_audio_frame_v2_t
    private var isFreed = false

    /// The sample rate in Hz (for example, `48000`).
    public var sampleRate: Int { Int(frame.sample_rate) }

    /// The number of audio channels.
    public var channelCount: Int { Int(frame.no_channels) }

    /// The number of samples per channel in this frame.
    public var sampleCount: Int { Int(frame.no_samples) }

    /// The timecode of the frame, in 100-nanosecond intervals.
    public var timecode: Int64 { frame.timecode }

    /// The timestamp when the frame was submitted by the sender, in
    /// 100-nanosecond intervals, or `nil` if not available.
    public var timestamp: Int64? {
        frame.timestamp == NDIlib_recv_timestamp_undefined ? nil : frame.timestamp
    }

    /// The stride between channels, in bytes.
    public var channelStride: Int { Int(frame.channel_stride_in_bytes) }

    /// Per-frame metadata as an XML string, or `nil` if none was attached.
    public var metadata: String? {
        frame.p_metadata.map { String(cString: $0) }
    }

    /// Direct access to the interleaved audio sample data (32-bit float,
    /// planar layout).
    ///
    /// - Warning: This pointer is only valid while the frame has not been
    ///   freed.
    public var data: UnsafeBufferPointer<Float>? {
        guard !isFreed, let ptr = frame.p_data else { return nil }
        let totalSamples = channelCount * (channelStride / MemoryLayout<Float>.size)
        return UnsafeBufferPointer(start: ptr, count: totalSamples)
    }

    /// Returns the samples for a specific audio channel.
    ///
    /// - Parameter channel: The zero-based channel index.
    /// - Returns: A buffer of `Float` samples for the requested channel,
    ///   or `nil` if the frame has been freed or the index is out of range.
    public func samples(forChannel channel: Int) -> UnsafeBufferPointer<Float>? {
        guard !isFreed, let ptr = frame.p_data, channel < channelCount else { return nil }
        let channelOffset = channel * (channelStride / MemoryLayout<Float>.size)
        return UnsafeBufferPointer(start: ptr.advanced(by: channelOffset), count: sampleCount)
    }

    init(receiver: NDIlib_recv_instance_t, frame: NDIlib_audio_frame_v2_t) {
        self.receiver = receiver
        self.frame = frame
    }

    deinit {
        freeIfNeeded()
    }

    /// Releases the frame's audio data back to the NDI SDK.
    ///
    /// This is called automatically when the frame is deallocated, but you
    /// may call it earlier to free memory sooner.
    public func free() {
        freeIfNeeded()
    }

    private func freeIfNeeded() {
        guard !isFreed else { return }
        isFreed = true
        NDIlib_recv_free_audio_v2(receiver, &frame)
    }
}

// MARK: - Metadata Frame

/// A metadata frame received from an NDI source.
///
/// Metadata is delivered as an XML string and may accompany video or
/// audio frames.
public struct NDIMetadataFrame: Sendable {
    /// The metadata payload as an XML string.
    public let content: String

    /// The timecode of the frame, in 100-nanosecond intervals.
    public let timecode: Int64

    init(frame: NDIlib_metadata_frame_t) {
        self.content = frame.p_data.map { String(cString: $0) } ?? ""
        self.timecode = frame.timecode
    }
}

// MARK: - Supporting Types

/// A video pixel format identified by a four-character code (FourCC).
///
/// Use the predefined constants (e.g. ``uyvy``, ``bgra``) when
/// configuring an ``NDISender``.
public struct FourCC: Sendable, Hashable, CustomStringConvertible {
    /// The raw 32-bit FourCC value.
    public let rawValue: UInt32

    /// Creates a `FourCC` from the underlying C enum value.
    ///
    /// - Parameter value: The NDI SDK FourCC video type.
    public init(_ value: NDIlib_FourCC_video_type_e) {
        self.rawValue = UInt32(bitPattern: Int32(value.rawValue))
    }

    /// A human-readable four-character string representation of the code.
    public var description: String {
        let bytes = withUnsafeBytes(of: rawValue.littleEndian) { Array($0) }
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// 8-bit UYVY (4:2:2).
    public static let uyvy = FourCC(NDIlib_FourCC_video_type_UYVY)
    /// 8-bit UYVY with alpha (4:2:2:4).
    public static let uyva = FourCC(NDIlib_FourCC_video_type_UYVA)
    /// 16-bit YCbCr (4:2:2).
    public static let p216 = FourCC(NDIlib_FourCC_video_type_P216)
    /// 16-bit YCbCr with alpha (4:2:2:4).
    public static let pa16 = FourCC(NDIlib_FourCC_video_type_PA16)
    /// 8-bit planar YV12 (4:2:0).
    public static let yv12 = FourCC(NDIlib_FourCC_video_type_YV12)
    /// 8-bit planar I420 (4:2:0).
    public static let i420 = FourCC(NDIlib_FourCC_video_type_I420)
    /// 8-bit semi-planar NV12 (4:2:0).
    public static let nv12 = FourCC(NDIlib_FourCC_video_type_NV12)
    /// 8-bit BGRA (4:4:4:4).
    public static let bgra = FourCC(NDIlib_FourCC_video_type_BGRA)
    /// 8-bit BGRX — BGRA with the alpha channel ignored.
    public static let bgrx = FourCC(NDIlib_FourCC_video_type_BGRX)
    /// 8-bit RGBA (4:4:4:4).
    public static let rgba = FourCC(NDIlib_FourCC_video_type_RGBA)
    /// 8-bit RGBX — RGBA with the alpha channel ignored.
    public static let rgbx = FourCC(NDIlib_FourCC_video_type_RGBX)
}

/// The scan type of a video frame.
public enum FrameFormat: Sendable {
    /// A progressive (non-interlaced) frame.
    case progressive
    /// An interlaced frame containing both fields.
    case interlaced
    /// The first (top) field of an interlaced frame.
    case field0
    /// The second (bottom) field of an interlaced frame.
    case field1

    init(_ value: NDIlib_frame_format_type_e) {
        switch value {
        case NDIlib_frame_format_type_progressive: self = .progressive
        case NDIlib_frame_format_type_interleaved: self = .interlaced
        case NDIlib_frame_format_type_field_0: self = .field0
        case NDIlib_frame_format_type_field_1: self = .field1
        default: self = .progressive
        }
    }
}

/// The result of an ``NDIReceiver/capture(timeout:)`` call.
public enum CaptureResult: Sendable {
    /// A video frame was captured.
    case video(NDIVideoFrame)
    /// An audio frame was captured.
    case audio(NDIAudioFrame)
    /// A metadata frame was captured.
    case metadata(NDIMetadataFrame)
    /// No data was received within the timeout period.
    case none
    /// The connection to the source was lost.
    case error
    /// The source's settings (resolution, frame rate, etc.) have changed.
    case statusChange
}
