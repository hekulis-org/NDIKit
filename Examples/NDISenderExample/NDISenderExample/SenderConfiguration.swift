//
//  SenderConfiguration.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import AVFoundation
import NDIKit

/// Video resolution options.
enum VideoResolution: String, CaseIterable, Identifiable {
    case hd1080 = "1920×1080"
    case hd720 = "1280×720"

    var id: String { rawValue }

    var landscapeWidth: Int {
        switch self {
        case .hd1080: return 1920
        case .hd720: return 1280
        }
    }

    var landscapeHeight: Int {
        switch self {
        case .hd1080: return 1080
        case .hd720: return 720
        }
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .hd1080: return .hd1920x1080
        case .hd720: return .hd1280x720
        }
    }
}

/// Frame rate options.
enum VideoFrameRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue) FPS"
    }

    var cmTime: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(rawValue))
    }

    var ndiFrameRate: (numerator: Int, denominator: Int) {
        (numerator: rawValue * 1000, denominator: 1001)
    }
}

/// Represents a camera device for selection.
struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let position: AVCaptureDevice.Position
    let device: AVCaptureDevice

    static func == (lhs: CameraDevice, rhs: CameraDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// All user-configurable options for NDI sending.
struct SenderConfiguration: Sendable, Codable {
    /// Name of the NDI source.
    var senderName: String = "NDISenderExample (iOS)"

    /// NDI groups to publish (nil = default).
    var groups: String?

    /// Whether to clock video frames.
    var clockVideo: Bool = true

    /// Whether to clock audio frames.
    var clockAudio: Bool = true

    /// Selected camera device ID.
    var selectedCameraID: String?

    /// Video resolution.
    var resolution: VideoResolution = .hd720

    /// Frame rate.
    var frameRate: VideoFrameRate = .fps30

    var ndiConfiguration: NDISender.Configuration {
        let name = senderName.isEmpty ? nil : senderName
        return NDISender.Configuration(
            name: name,
            groups: groups,
            clockVideo: clockVideo,
            clockAudio: clockAudio
        )
    }

    // Codable conformance for enums
    enum CodingKeys: String, CodingKey {
        case senderName, groups, clockVideo, clockAudio, selectedCameraID, resolution, frameRate
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        senderName = try container.decodeIfPresent(String.self, forKey: .senderName) ?? "NDISenderExample (iOS)"
        groups = try container.decodeIfPresent(String.self, forKey: .groups)
        clockVideo = try container.decodeIfPresent(Bool.self, forKey: .clockVideo) ?? true
        clockAudio = try container.decodeIfPresent(Bool.self, forKey: .clockAudio) ?? true
        selectedCameraID = try container.decodeIfPresent(String.self, forKey: .selectedCameraID)
        if let resolutionRaw = try container.decodeIfPresent(String.self, forKey: .resolution) {
            resolution = VideoResolution(rawValue: resolutionRaw) ?? .hd720
        }
        if let frameRateRaw = try container.decodeIfPresent(Int.self, forKey: .frameRate) {
            frameRate = VideoFrameRate(rawValue: frameRateRaw) ?? .fps30
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderName, forKey: .senderName)
        try container.encodeIfPresent(groups, forKey: .groups)
        try container.encode(clockVideo, forKey: .clockVideo)
        try container.encode(clockAudio, forKey: .clockAudio)
        try container.encodeIfPresent(selectedCameraID, forKey: .selectedCameraID)
        try container.encode(resolution.rawValue, forKey: .resolution)
        try container.encode(frameRate.rawValue, forKey: .frameRate)
    }
}
