import Foundation
import NDIKitC

/// Sends video, audio, and metadata over the network via NDI.
///
/// Create a sender, then call ``sendVideo(width:height:fourCC:frameRate:aspectRatio:formatType:timecode:data:lineStride:metadata:)``
/// or ``sendVideoAsync(width:height:fourCC:frameRate:aspectRatio:formatType:timecode:data:lineStride:metadata:)``
/// to transmit frames to connected receivers.
///
/// ```swift
/// let config = NDISender.Configuration(name: "My Source")
/// guard let sender = NDISender(configuration: config) else { return }
/// sender.sendVideo(width: 1920, height: 1080, ...)
/// ```
public final class NDISender: @unchecked Sendable {
    private let instance: NDIlib_send_instance_t

    /// Configuration options for creating an ``NDISender``.
    public struct Configuration: Sendable {
        /// The name that receivers will see for this source.
        ///
        /// Pass `nil` to let the SDK generate a default name.
        public var name: String?

        /// The NDI groups this source belongs to.
        ///
        /// Pass `nil` to use the default groups.
        public var groups: String?

        /// A Boolean value that indicates whether the sender should
        /// clock video frame submissions to the declared frame rate.
        public var clockVideo: Bool

        /// A Boolean value that indicates whether the sender should
        /// clock audio frame submissions to the declared sample rate.
        public var clockAudio: Bool

        /// Creates a sender configuration.
        ///
        /// - Parameters:
        ///   - name: The source name visible to receivers. `nil` uses a
        ///     default name.
        ///   - groups: NDI groups this source belongs to. `nil` uses the
        ///     default groups.
        ///   - clockVideo: Whether to clock video submissions. Defaults
        ///     to `true`.
        ///   - clockAudio: Whether to clock audio submissions. Defaults
        ///     to `true`.
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

    /// Creates a sender with the specified configuration.
    ///
    /// - Parameter configuration: The configuration to use.
    /// - Returns: A new sender, or `nil` if the NDI library could not
    ///   create the sender instance.
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

    /// Sends a video frame synchronously.
    ///
    /// This call blocks until the frame has been submitted to the NDI SDK.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - fourCC: The pixel format of the frame data.
    ///   - frameRate: Frame rate expressed as a fraction
    ///     (numerator / denominator). For example, 30 fps is `(30000, 1001)`.
    ///   - aspectRatio: Picture aspect ratio. Pass `0` for square pixels.
    ///   - formatType: Whether the frame is progressive or interlaced.
    ///     Defaults to ``FrameFormat/progressive``.
    ///   - timecode: An optional timecode in 100-nanosecond intervals.
    ///     Pass `nil` to let the SDK synthesize a timecode.
    ///   - data: A pointer to the raw pixel data.
    ///   - lineStride: The number of bytes per row in the pixel buffer.
    ///   - metadata: Optional XML metadata to attach to the frame.
    ///
    /// - Important: The memory backing `data` must remain valid for the
    ///   duration of this call.
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

    /// Sends a video frame asynchronously.
    ///
    /// Returns immediately while the NDI SDK transmits the frame in the
    /// background.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - fourCC: The pixel format of the frame data.
    ///   - frameRate: Frame rate expressed as a fraction
    ///     (numerator / denominator). For example, 30 fps is `(30000, 1001)`.
    ///   - aspectRatio: Picture aspect ratio. Pass `0` for square pixels.
    ///   - formatType: Whether the frame is progressive or interlaced.
    ///     Defaults to ``FrameFormat/progressive``.
    ///   - timecode: An optional timecode in 100-nanosecond intervals.
    ///     Pass `nil` to let the SDK synthesize a timecode.
    ///   - data: A pointer to the raw pixel data.
    ///   - lineStride: The number of bytes per row in the pixel buffer.
    ///   - metadata: Optional XML metadata to attach to the frame.
    ///
    /// - Important: The memory backing `data` must remain valid until the
    ///   **next** call to a send-video method, because the SDK may still be
    ///   reading from the buffer.
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

    /// The number of receivers currently connected to this sender.
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
