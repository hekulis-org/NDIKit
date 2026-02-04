import Foundation
import NDIKitC

/// Sends video, audio, and metadata to an NDI receiver.
public final class NDISender: @unchecked Sendable {
    private let instance: NDIlib_send_instance_t

    /// Configuration options for creating a sender.
    public struct Configuration: Sendable {
        /// Name of the NDI source.
        public var name: String?

        /// Groups that this source belongs to.
        public var groups: String?

        /// Whether to clock video frames.
        public var clockVideo: Bool

        /// Whether to clock audio frames.
        public var clockAudio: Bool

        public init(
            name: String? = nil,
            groups: String? = nil,
            clockVideo: Bool = true,
            clockAudio: Bool = true
        ) {
            self.name = name
            self.groups = groups
            self.clockVideo = clockVideo
            self.clockAudio = clockAudio
        }
    }

    /// Create a new sender with the specified configuration.
    public init?(configuration: Configuration) {
        let instance: NDIlib_send_instance_t? = configuration.name.withOptionalCString { namePtr in
            configuration.groups.withOptionalCString { groupsPtr in
                var settings = NDIlib_send_create_t()
                settings.p_ndi_name = namePtr
                settings.p_groups = groupsPtr
                settings.clock_video = configuration.clockVideo
                settings.clock_audio = configuration.clockAudio
                return NDIlib_send_create(&settings)
            }
        }

        guard let instance else { return nil }
        self.instance = instance
    }

    deinit {
        NDIlib_send_destroy(instance)
    }

    /// Send a video frame using the provided buffer.
    /// - Important: The memory backing `data` must stay valid for the duration of this call.
    public func sendVideo(
        width: Int,
        height: Int,
        fourCC: FourCC,
        frameRate: (numerator: Int, denominator: Int),
        aspectRatio: Float,
        formatType: FrameFormat = .progressive,
        timecode: Int64? = nil,
        data: UnsafeMutablePointer<UInt8>,
        lineStride: Int,
        metadata: String? = nil
    ) {
        var frame = NDIlib_video_frame_v2_t()
        frame.xres = Int32(width)
        frame.yres = Int32(height)
        frame.FourCC = cFourCC(from: fourCC)
        frame.frame_rate_N = Int32(frameRate.numerator)
        frame.frame_rate_D = Int32(frameRate.denominator)
        frame.picture_aspect_ratio = aspectRatio
        frame.frame_format_type = cFrameFormat(from: formatType)
        frame.timecode = timecode ?? NDIlib_send_timecode_synthesize
        frame.p_data = data
        frame.line_stride_in_bytes = Int32(lineStride)

        if let metadata {
            metadata.withCString { metadataPtr in
                frame.p_metadata = metadataPtr
                NDIlib_send_send_video_v2(instance, &frame)
            }
        } else {
            frame.p_metadata = nil
            NDIlib_send_send_video_v2(instance, &frame)
        }
    }

    /// Send a video frame asynchronously.
    /// - Important: The memory backing `data` must stay valid until the next call to send a video frame.
    public func sendVideoAsync(
        width: Int,
        height: Int,
        fourCC: FourCC,
        frameRate: (numerator: Int, denominator: Int),
        aspectRatio: Float,
        formatType: FrameFormat = .progressive,
        timecode: Int64? = nil,
        data: UnsafeMutablePointer<UInt8>,
        lineStride: Int,
        metadata: String? = nil
    ) {
        var frame = NDIlib_video_frame_v2_t()
        frame.xres = Int32(width)
        frame.yres = Int32(height)
        frame.FourCC = cFourCC(from: fourCC)
        frame.frame_rate_N = Int32(frameRate.numerator)
        frame.frame_rate_D = Int32(frameRate.denominator)
        frame.picture_aspect_ratio = aspectRatio
        frame.frame_format_type = cFrameFormat(from: formatType)
        frame.timecode = timecode ?? NDIlib_send_timecode_synthesize
        frame.p_data = data
        frame.line_stride_in_bytes = Int32(lineStride)

        if let metadata {
            metadata.withCString { metadataPtr in
                frame.p_metadata = metadataPtr
                NDIlib_send_send_video_async_v2(instance, &frame)
            }
        } else {
            frame.p_metadata = nil
            NDIlib_send_send_video_async_v2(instance, &frame)
        }
    }

    /// The current number of connections to this sender.
    public var connectionCount: Int {
        Int(NDIlib_send_get_no_connections(instance, 0))
    }

    private func cFourCC(from fourCC: FourCC) -> NDIlib_FourCC_video_type_e {
        NDIlib_FourCC_video_type_e(rawValue: fourCC.rawValue)
    }

    private func cFrameFormat(from format: FrameFormat) -> NDIlib_frame_format_type_e {
        switch format {
        case .progressive:
            return NDIlib_frame_format_type_progressive
        case .interlaced:
            return NDIlib_frame_format_type_interleaved
        case .field0:
            return NDIlib_frame_format_type_field_0
        case .field1:
            return NDIlib_frame_format_type_field_1
        }
    }
}
