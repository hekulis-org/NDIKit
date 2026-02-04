//
//  ReceiverConfiguration.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import NDIKit

/// All user-configurable options for NDI receiving.
struct ReceiverConfiguration: Sendable, Codable {
    // MARK: - Video Settings

    /// Color format preference. `.bgrxBgra` converts everything to BGRA/BGRX which is easiest to display.
    /// Use `.best` for highest quality (16-bit) if your converter supports P216.
    var colorFormat: ColorFormatOption = .bgrxBgra

    /// Bandwidth/quality setting.
    var bandwidth: BandwidthOption = .highest

    /// Allow interlaced video fields.
    var allowVideoFields: Bool = true

    // MARK: - Receiver Identity

    /// Name shown to NDI senders.
    var receiverName: String = "NDIReceiverExample"

    // MARK: - Source Discovery

    /// Include sources on local machine.
    var showLocalSources: Bool = true

    /// NDI groups to search (nil = default).
    var groups: String?

    /// Additional IPs to query (comma-separated).
    var extraIPs: String?

    // MARK: - Enums

    enum ColorFormatOption: String, Sendable, Codable, CaseIterable {
        case bgrxBgra
        case uyvyBgra
        case rgbxRgba
        case uyvyRgba
        case fastest
        case best

        var ndiColorFormat: NDIReceiver.ColorFormat {
            switch self {
            case .bgrxBgra: return .bgrxBgra
            case .uyvyBgra: return .uyvyBgra
            case .rgbxRgba: return .rgbxRgba
            case .uyvyRgba: return .uyvyRgba
            case .fastest: return .fastest
            case .best: return .best
            }
        }
    }

    enum BandwidthOption: String, Sendable, Codable, CaseIterable {
        case metadataOnly
        case audioOnly
        case lowest
        case highest

        var ndiBandwidth: NDIReceiver.Bandwidth {
            switch self {
            case .metadataOnly: return .metadataOnly
            case .audioOnly: return .audioOnly
            case .lowest: return .lowest
            case .highest: return .highest
            }
        }
    }

    // MARK: - Convenience

    var finderConfiguration: NDIFinder.Configuration {
        NDIFinder.Configuration(
            showLocalSources: showLocalSources,
            groups: groups,
            extraIPs: extraIPs
        )
    }

    func receiverConfiguration(for source: NDISource?) -> NDIReceiver.Configuration {
        NDIReceiver.Configuration(
            source: source,
            colorFormat: colorFormat.ndiColorFormat,
            bandwidth: bandwidth.ndiBandwidth,
            allowVideoFields: allowVideoFields,
            name: receiverName
        )
    }
}
