import NDIKitC

/// Receives video, audio, and metadata from an NDI source.
public final class NDIReceiver: @unchecked Sendable {
    private let instance: NDIlib_recv_instance_t

    /// Bandwidth settings for receiving.
    public enum Bandwidth: Sendable {
        case metadataOnly
        case audioOnly
        case lowest
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

    /// Color format preferences for receiving video.
    public enum ColorFormat: Sendable {
        case bgrxBgra
        case uyvyBgra
        case rgbxRgba
        case uyvyRgba
        case fastest
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

    /// Configuration options for creating a receiver.
    public struct Configuration: Sendable {
        /// The source to connect to.
        public var source: NDISource?

        /// Preferred color format for video.
        public var colorFormat: ColorFormat

        /// Bandwidth setting.
        public var bandwidth: Bandwidth

        /// Whether to allow interlaced video fields.
        public var allowVideoFields: Bool

        /// Name for this receiver.
        public var name: String?

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

    /// Create a new receiver with default configuration.
    public convenience init?() {
        self.init(configuration: Configuration())
    }

    /// Create a new receiver with the specified configuration.
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

    /// Connect to a source. Pass nil to disconnect.
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

    /// The number of current connections (0 or 1).
    public var connectionCount: Int {
        Int(NDIlib_recv_get_no_connections(instance))
    }

    /// Set the tally state to send upstream.
    public func setTally(onProgram: Bool, onPreview: Bool) {
        var tally = NDIlib_tally_t()
        tally.on_program = onProgram
        tally.on_preview = onPreview
        NDIlib_recv_set_tally(instance, &tally)
    }

    // MARK: - Frame Capture

    /// Capture the next available frame (video, audio, or metadata).
    /// - Parameter timeout: Maximum time to wait in milliseconds.
    /// - Returns: The captured frame, or `.none` if timed out, or `.error` if disconnected.
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

    /// Capture only video frames, ignoring audio and metadata.
    /// - Parameter timeout: Maximum time to wait in milliseconds.
    /// - Returns: A video frame, or nil if timed out or an error occurred.
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

    /// Capture only audio frames, ignoring video and metadata.
    /// - Parameter timeout: Maximum time to wait in milliseconds.
    /// - Returns: An audio frame, or nil if timed out or an error occurred.
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

    /// Performance statistics for the receiver.
    public struct Performance: Sendable {
        public let videoFrames: Int64
        public let audioFrames: Int64
        public let metadataFrames: Int64
    }

    /// Get the total number of frames received.
    public var totalFrames: Performance {
        var total = NDIlib_recv_performance_t()
        NDIlib_recv_get_performance(instance, &total, nil)
        return Performance(
            videoFrames: total.video_frames,
            audioFrames: total.audio_frames,
            metadataFrames: total.metadata_frames
        )
    }

    /// Get the number of frames that were dropped.
    public var droppedFrames: Performance {
        var dropped = NDIlib_recv_performance_t()
        NDIlib_recv_get_performance(instance, nil, &dropped)
        return Performance(
            videoFrames: dropped.video_frames,
            audioFrames: dropped.audio_frames,
            metadataFrames: dropped.metadata_frames
        )
    }

    /// Current queue depths.
    public struct QueueDepth: Sendable {
        public let videoFrames: Int
        public let audioFrames: Int
        public let metadataFrames: Int
    }

    /// Get the current queue depths for each frame type.
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
