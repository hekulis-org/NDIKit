import NDIKitC

/// Receives video, audio, and metadata from an NDI source.
///
/// Create a receiver, connect it to an ``NDISource``, then call
/// ``capture(timeout:)`` (or the typed variants) to pull frames.
///
/// ```swift
/// guard let receiver = NDIReceiver() else { return }
/// receiver.connect(to: source)
///
/// switch receiver.capture() {
/// case .video(let frame):
///     // process video
/// case .audio(let frame):
///     // process audio
/// default:
///     break
/// }
/// ```
public final class NDIReceiver: @unchecked Sendable {
    private let instance: NDIlib_recv_instance_t

    /// The bandwidth mode used when receiving from a source.
    ///
    /// Higher bandwidth modes deliver better quality at the cost of
    /// increased network usage.
    public enum Bandwidth: Sendable {
        /// Receive metadata only — no video or audio.
        case metadataOnly
        /// Receive audio only — no video.
        case audioOnly
        /// Receive the lowest quality video and audio.
        case lowest
        /// Receive the highest quality video and audio.
        case highest

        var cValue: NDIlib_recv_bandwidth_e {
            switch self {
            case .metadataOnly: return NDIlib_recv_bandwidth_metadata_only
            case .audioOnly: return NDIlib_recv_bandwidth_audio_only
            case .lowest: return NDIlib_recv_bandwidth_lowest
            case .highest: return NDIlib_recv_bandwidth_highest
            }
        }
    }

    /// The preferred color format for received video frames.
    ///
    /// The NDI SDK will convert frames to the requested format when
    /// possible.
    public enum ColorFormat: Sendable {
        /// BGRX for opaque frames, BGRA for frames with alpha.
        case bgrxBgra
        /// UYVY for opaque frames, BGRA for frames with alpha.
        case uyvyBgra
        /// RGBX for opaque frames, RGBA for frames with alpha.
        case rgbxRgba
        /// UYVY for opaque frames, RGBA for frames with alpha.
        case uyvyRgba
        /// The fastest format for the current platform.
        case fastest
        /// The highest quality format available.
        case best

        var cValue: NDIlib_recv_color_format_e {
            switch self {
            case .bgrxBgra: return NDIlib_recv_color_format_BGRX_BGRA
            case .uyvyBgra: return NDIlib_recv_color_format_UYVY_BGRA
            case .rgbxRgba: return NDIlib_recv_color_format_RGBX_RGBA
            case .uyvyRgba: return NDIlib_recv_color_format_UYVY_RGBA
            case .fastest: return NDIlib_recv_color_format_fastest
            case .best: return NDIlib_recv_color_format_best
            }
        }
    }

    /// Configuration options for creating an ``NDIReceiver``.
    public struct Configuration: Sendable {
        /// The source to connect to immediately, or `nil` to connect later
        /// via ``NDIReceiver/connect(to:)``.
        public var source: NDISource?

        /// The preferred color format for received video frames.
        public var colorFormat: ColorFormat

        /// The bandwidth mode to use when receiving.
        public var bandwidth: Bandwidth

        /// A Boolean value that indicates whether the receiver should
        /// deliver interlaced video as separate fields.
        public var allowVideoFields: Bool

        /// A display name for this receiver.
        ///
        /// Pass `nil` to let the SDK generate a default name.
        public var name: String?

        /// Creates a receiver configuration.
        ///
        /// - Parameters:
        ///   - source: The source to connect to, or `nil`.
        ///   - colorFormat: Preferred video color format. Defaults to
        ///     ``ColorFormat/uyvyBgra``.
        ///   - bandwidth: Bandwidth mode. Defaults to
        ///     ``Bandwidth/highest``.
        ///   - allowVideoFields: Whether to allow interlaced fields.
        ///     Defaults to `true`.
        ///   - name: A display name for the receiver, or `nil`.
        public init(
            source: NDISource? = nil,
            colorFormat: ColorFormat = .uyvyBgra,
            bandwidth: Bandwidth = .highest,
            allowVideoFields: Bool = true,
            name: String? = nil
        ) {
            self.source = source
            self.colorFormat = colorFormat
            self.bandwidth = bandwidth
            self.allowVideoFields = allowVideoFields
            self.name = name
        }
    }

    /// Creates a receiver with the default configuration.
    ///
    /// - Returns: A new receiver, or `nil` if the NDI library could not
    ///   create the receiver instance.
    public convenience init?() {
        self.init(configuration: Configuration())
    }

    /// Creates a receiver with the specified configuration.
    ///
    /// - Parameter configuration: The configuration to use.
    /// - Returns: A new receiver, or `nil` if the NDI library could not
    ///   create the receiver instance.
    public init?(configuration: Configuration) {
        let instance: NDIlib_recv_instance_t? = configuration.name.withOptionalCString { namePtr in
            if let source = configuration.source {
                return source.withCSource { cSource in
                    var settings = NDIlib_recv_create_v3_t()
                    settings.source_to_connect_to = cSource
                    settings.color_format = configuration.colorFormat.cValue
                    settings.bandwidth = configuration.bandwidth.cValue
                    settings.allow_video_fields = configuration.allowVideoFields
                    settings.p_ndi_recv_name = namePtr
                    return NDIlib_recv_create_v3(&settings)
                }
            } else {
                var settings = NDIlib_recv_create_v3_t()
                settings.color_format = configuration.colorFormat.cValue
                settings.bandwidth = configuration.bandwidth.cValue
                settings.allow_video_fields = configuration.allowVideoFields
                settings.p_ndi_recv_name = namePtr
                return NDIlib_recv_create_v3(&settings)
            }
        }

        guard let instance else { return nil }
        self.instance = instance
    }

    deinit {
        NDIlib_recv_destroy(instance)
    }

    /// Connects to the specified source, or disconnects if `nil`.
    ///
    /// - Parameter source: The source to connect to, or `nil` to
    ///   disconnect from the current source.
    public func connect(to source: NDISource?) {
        if let source {
            source.withCSource { cSource in
                var mutableSource = cSource
                NDIlib_recv_connect(instance, &mutableSource)
            }
        } else {
            NDIlib_recv_connect(instance, nil)
        }
    }

    /// The number of active connections to the source (typically `0` or `1`).
    public var connectionCount: Int {
        Int(NDIlib_recv_get_no_connections(instance))
    }

    /// Sends tally information upstream to the connected source.
    ///
    /// - Parameters:
    ///   - onProgram: `true` if this receiver's source is on program
    ///     (live / on-air).
    ///   - onPreview: `true` if this receiver's source is on preview.
    public func setTally(onProgram: Bool, onPreview: Bool) {
        var tally = NDIlib_tally_t()
        tally.on_program = onProgram
        tally.on_preview = onPreview
        NDIlib_recv_set_tally(instance, &tally)
    }

    // MARK: - Frame Capture

    /// Captures the next available frame of any type.
    ///
    /// - Parameter timeout: The maximum time to wait, in milliseconds.
    ///   Defaults to `5000`.
    /// - Returns: A ``CaptureResult`` containing the captured frame, or
    ///   ``CaptureResult/none`` if the call timed out, or
    ///   ``CaptureResult/error`` if the connection was lost.
    public func capture(timeout: UInt32 = 5000) -> CaptureResult {
        var videoFrame = NDIlib_video_frame_v2_t()
        var audioFrame = NDIlib_audio_frame_v2_t()
        var metadataFrame = NDIlib_metadata_frame_t()

        let frameType = NDIlib_recv_capture_v2(
            instance,
            &videoFrame,
            &audioFrame,
            &metadataFrame,
            timeout
        )

        switch frameType {
        case NDIlib_frame_type_video:
            return .video(NDIVideoFrame(receiver: instance, frame: videoFrame))

        case NDIlib_frame_type_audio:
            return .audio(NDIAudioFrame(receiver: instance, frame: audioFrame))

        case NDIlib_frame_type_metadata:
            let result = NDIMetadataFrame(frame: metadataFrame)
            NDIlib_recv_free_metadata(instance, &metadataFrame)
            return .metadata(result)

        case NDIlib_frame_type_error:
            return .error

        case NDIlib_frame_type_status_change:
            return .statusChange

        default:
            return .none
        }
    }

    /// Captures only video frames, ignoring audio and metadata.
    ///
    /// - Parameter timeout: The maximum time to wait, in milliseconds.
    ///   Defaults to `5000`.
    /// - Returns: A video frame, or `nil` if the call timed out or an
    ///   error occurred.
    public func captureVideo(timeout: UInt32 = 5000) -> NDIVideoFrame? {
        var videoFrame = NDIlib_video_frame_v2_t()

        let frameType = NDIlib_recv_capture_v2(
            instance,
            &videoFrame,
            nil,
            nil,
            timeout
        )

        if frameType == NDIlib_frame_type_video {
            return NDIVideoFrame(receiver: instance, frame: videoFrame)
        }
        return nil
    }

    /// Captures only audio frames, ignoring video and metadata.
    ///
    /// - Parameter timeout: The maximum time to wait, in milliseconds.
    ///   Defaults to `5000`.
    /// - Returns: An audio frame, or `nil` if the call timed out or an
    ///   error occurred.
    public func captureAudio(timeout: UInt32 = 5000) -> NDIAudioFrame? {
        var audioFrame = NDIlib_audio_frame_v2_t()

        let frameType = NDIlib_recv_capture_v2(
            instance,
            nil,
            &audioFrame,
            nil,
            timeout
        )

        if frameType == NDIlib_frame_type_audio {
            return NDIAudioFrame(receiver: instance, frame: audioFrame)
        }
        return nil
    }

    // MARK: - Performance Monitoring

    /// Cumulative frame counts reported by the receiver.
    public struct Performance: Sendable {
        /// The number of video frames.
        public let videoFrames: Int64
        /// The number of audio frames.
        public let audioFrames: Int64
        /// The number of metadata frames.
        public let metadataFrames: Int64
    }

    /// The total number of frames received since the connection was
    /// established.
    public var totalFrames: Performance {
        var total = NDIlib_recv_performance_t()
        NDIlib_recv_get_performance(instance, &total, nil)
        return Performance(
            videoFrames: total.video_frames,
            audioFrames: total.audio_frames,
            metadataFrames: total.metadata_frames
        )
    }

    /// The number of frames that were dropped since the connection was
    /// established.
    public var droppedFrames: Performance {
        var dropped = NDIlib_recv_performance_t()
        NDIlib_recv_get_performance(instance, nil, &dropped)
        return Performance(
            videoFrames: dropped.video_frames,
            audioFrames: dropped.audio_frames,
            metadataFrames: dropped.metadata_frames
        )
    }

    /// The number of frames currently buffered in each receive queue.
    public struct QueueDepth: Sendable {
        /// The number of buffered video frames.
        public let videoFrames: Int
        /// The number of buffered audio frames.
        public let audioFrames: Int
        /// The number of buffered metadata frames.
        public let metadataFrames: Int
    }

    /// The current queue depths for video, audio, and metadata.
    public var queueDepth: QueueDepth {
        var queue = NDIlib_recv_queue_t()
        NDIlib_recv_get_queue(instance, &queue)
        return QueueDepth(
            videoFrames: Int(queue.video_frames),
            audioFrames: Int(queue.audio_frames),
            metadataFrames: Int(queue.metadata_frames)
        )
    }
}
