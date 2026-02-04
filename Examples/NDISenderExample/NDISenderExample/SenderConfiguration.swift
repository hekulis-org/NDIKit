//
//  SenderConfiguration.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import NDIKit

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

    var ndiConfiguration: NDISender.Configuration {
        let name = senderName.isEmpty ? nil : senderName
        return NDISender.Configuration(
            name: name,
            groups: groups,
            clockVideo: clockVideo,
            clockAudio: clockAudio
        )
    }
}
