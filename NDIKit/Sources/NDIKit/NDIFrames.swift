import NDIKitC
import Foundation

// MARK: - Video Frame

/// A received video frame from an NDI source.
/// The frame data is valid until `free()` is called or the frame is deallocated.
public final class NDIVideoFrame: @unchecked Sendable {
    private let receiver: NDIlib_recv_instance_t
    private var frame: NDIlib_video_frame_v2_t
    private var isFreed = false

    /// Frame width in pixels.
    public var width: Int { Int(frame.xres) }

    /// Frame height in pixels.
    public var height: Int { Int(frame.yres) }

    /// The pixel format (FourCC code).
    public var fourCC: FourCC { FourCC(frame.FourCC) }

    /// Frame rate as a fraction (numerator/denominator).
    public var frameRate: (numerator: Int, denominator: Int) {
        (Int(frame.frame_rate_N), Int(frame.frame_rate_D))
    }

    /// Frame rate as a floating point value.
    public var frameRateValue: Double {
        Double(frame.frame_rate_N) / Double(frame.frame_rate_D)
    }

    /// Picture aspect ratio. Zero means square pixels.
    public var aspectRatio: Float { frame.picture_aspect_ratio }

    /// Whether this is a progressive or interlaced frame.
    public var formatType: FrameFormat { FrameFormat(frame.frame_format_type) }

    /// Timecode in 100-nanosecond intervals.
    public var timecode: Int64 { frame.timecode }

    /// Timestamp when the frame was submitted by the sender (100-nanosecond intervals).
    /// Returns nil if not available.
    public var timestamp: Int64? {
        frame.timestamp == NDIlib_recv_timestamp_undefined ? nil : frame.timestamp
    }

    /// Line stride in bytes.
    public var lineStride: Int { Int(frame.line_stride_in_bytes) }

    /// Per-frame metadata as XML string, if present.
    public var metadata: String? {
        frame.p_metadata.map { String(cString: $0) }
    }

    /// Direct access to the frame's pixel data.
    /// - Warning: Only valid while the frame has not been freed.
    public var data: UnsafeBufferPointer<UInt8>? {
        guard !isFreed, let ptr = frame.p_data else { return nil }
        let size = lineStride * height
        return UnsafeBufferPointer(start: ptr, count: size)
    }

    /// Copy the frame data to a Foundation Data object.
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

    /// Explicitly free the frame data. Called automatically on deallocation.
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

/// A received audio frame from an NDI source.
/// The frame data is valid until `free()` is called or the frame is deallocated.
public final class NDIAudioFrame: @unchecked Sendable {
    private let receiver: NDIlib_recv_instance_t
    private var frame: NDIlib_audio_frame_v2_t
    private var isFreed = false

    /// Sample rate in Hz (e.g., 48000).
    public var sampleRate: Int { Int(frame.sample_rate) }

    /// Number of audio channels.
    public var channelCount: Int { Int(frame.no_channels) }

    /// Number of samples per channel.
    public var sampleCount: Int { Int(frame.no_samples) }

    /// Timecode in 100-nanosecond intervals.
    public var timecode: Int64 { frame.timecode }

    /// Timestamp when the frame was submitted by the sender (100-nanosecond intervals).
    /// Returns nil if not available.
    public var timestamp: Int64? {
        frame.timestamp == NDIlib_recv_timestamp_undefined ? nil : frame.timestamp
    }

    /// Stride between channels in bytes.
    public var channelStride: Int { Int(frame.channel_stride_in_bytes) }

    /// Per-frame metadata as XML string, if present.
    public var metadata: String? {
        frame.p_metadata.map { String(cString: $0) }
    }

    /// Direct access to the audio sample data (32-bit float, planar).
    /// - Warning: Only valid while the frame has not been freed.
    public var data: UnsafeBufferPointer<Float>? {
        guard !isFreed, let ptr = frame.p_data else { return nil }
        let totalSamples = channelCount * (channelStride / MemoryLayout<Float>.size)
        return UnsafeBufferPointer(start: ptr, count: totalSamples)
    }

    /// Get samples for a specific channel.
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

    /// Explicitly free the frame data. Called automatically on deallocation.
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

/// A received metadata frame from an NDI source.
public struct NDIMetadataFrame: Sendable {
    /// The metadata content as an XML string.
    public let content: String

    /// Timecode in 100-nanosecond intervals.
    public let timecode: Int64

    init(frame: NDIlib_metadata_frame_t) {
        self.content = frame.p_data.map { String(cString: $0) } ?? ""
        self.timecode = frame.timecode
    }
}

// MARK: - Supporting Types

/// Video pixel format (FourCC code).
public struct FourCC: Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(_ value: NDIlib_FourCC_video_type_e) {
        self.rawValue = UInt32(bitPattern: Int32(value.rawValue))
    }

    public var description: String {
        let bytes = withUnsafeBytes(of: rawValue.littleEndian) { Array($0) }
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    public static let uyvy = FourCC(NDIlib_FourCC_video_type_UYVY)
    public static let uyva = FourCC(NDIlib_FourCC_video_type_UYVA)
    public static let p216 = FourCC(NDIlib_FourCC_video_type_P216)
    public static let pa16 = FourCC(NDIlib_FourCC_video_type_PA16)
    public static let yv12 = FourCC(NDIlib_FourCC_video_type_YV12)
    public static let i420 = FourCC(NDIlib_FourCC_video_type_I420)
    public static let nv12 = FourCC(NDIlib_FourCC_video_type_NV12)
    public static let bgra = FourCC(NDIlib_FourCC_video_type_BGRA)
    public static let bgrx = FourCC(NDIlib_FourCC_video_type_BGRX)
    public static let rgba = FourCC(NDIlib_FourCC_video_type_RGBA)
    public static let rgbx = FourCC(NDIlib_FourCC_video_type_RGBX)
}

/// Video frame format type.
public enum FrameFormat: Sendable {
    case progressive
    case interlaced
    case field0
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

/// Result of a capture operation.
public enum CaptureResult: Sendable {
    /// A video frame was captured.
    case video(NDIVideoFrame)
    /// An audio frame was captured.
    case audio(NDIAudioFrame)
    /// A metadata frame was captured.
    case metadata(NDIMetadataFrame)
    /// No data was received within the timeout.
    case none
    /// The connection was lost.
    case error
    /// The source settings have changed.
    case statusChange
}
