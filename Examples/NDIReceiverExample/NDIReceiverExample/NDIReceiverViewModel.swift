//
//  NDIReceiverViewModel.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import CoreGraphics
import Foundation
import NDIKit

/// Manages NDI source discovery and video capture.
@MainActor
@Observable
final class NDIReceiverViewModel {

    // MARK: - Published State

    /// Discovered NDI sources on the network.
    private(set) var sources: [NDISource] = []

    /// The currently selected source.
    var selectedSource: NDISource? {
        didSet {
            if selectedSource != oldValue {
                handleSourceSelection()
            }
        }
    }

    /// The current video frame to display.
    private(set) var currentFrame: CGImage?

    /// Whether we are connected to a source.
    private(set) var isConnected = false

    /// Information about the current video frame.
    private(set) var frameInfo: FrameInfo?

    /// Configuration options.
    var configuration = ReceiverConfiguration()

    /// Error message if something goes wrong.
    private(set) var errorMessage: String?

    // MARK: - Frame Info

    struct FrameInfo: Sendable {
        let width: Int
        let height: Int
        let frameRate: Double
        let formatDescription: String
    }

    // MARK: - Private State

    private var finder: NDIFinder?
    private var receiver: NDIReceiver?
    private var discoveryTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {}

    // MARK: - Source Discovery

    /// Start discovering NDI sources on the network.
    func startDiscovery() {
        guard finder == nil else { return }

        finder = NDIFinder(configuration: configuration.finderConfiguration)
        guard finder != nil else {
            errorMessage = "Failed to create NDI finder"
            return
        }

        errorMessage = nil

        discoveryTask = Task.detached { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let finder = await self.finder else { break }

                // Wait for source list to change (blocking call)
                let changed = finder.waitForSources(timeout: 1000)

                if changed {
                    let newSources = finder.sources
                    await MainActor.run {
                        self.sources = newSources
                    }
                }
            }
        }
    }

    /// Stop discovering NDI sources.
    func stopDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
        finder = nil
    }

    // MARK: - Connection

    /// Handle source selection changes.
    private func handleSourceSelection() {
        if let source = selectedSource {
            connect(to: source)
        } else {
            disconnect()
        }
    }

    /// Connect to the specified NDI source.
    func connect(to source: NDISource) {
        // Disconnect from any existing source
        disconnect()

        // Create receiver with configuration
        let receiverConfig = configuration.receiverConfiguration(for: source)
        receiver = NDIReceiver(configuration: receiverConfig)

        guard receiver != nil else {
            errorMessage = "Failed to create NDI receiver"
            return
        }

        isConnected = true
        errorMessage = nil

        startCapture()
    }

    /// Disconnect from the current source.
    func disconnect() {
        captureTask?.cancel()
        captureTask = nil

        receiver = nil
        isConnected = false
        currentFrame = nil
        frameInfo = nil
    }

    // MARK: - Capture

    /// Start the capture loop.
    private func startCapture() {
        captureTask = Task.detached { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard let receiver = await self.receiver else { break }

                let result = receiver.capture(timeout: 100)

                switch result {
                case .video(let frame):
                    let fourCC = frame.fourCC
                    print("NDIReceiverViewModel: Received frame \(frame.width)x\(frame.height), format: \(fourCC)")

                    let image = VideoFrameConverter.convert(frame)
                    if image == nil {
                        print("NDIReceiverViewModel: Frame conversion returned nil")
                    }

                    let info = FrameInfo(
                        width: frame.width,
                        height: frame.height,
                        frameRate: frame.frameRateValue,
                        formatDescription: self.formatDescription(for: frame)
                    )

                    await MainActor.run {
                        self.currentFrame = image
                        self.frameInfo = info
                    }

                case .error:
                    await MainActor.run {
                        self.errorMessage = "Connection lost"
                        self.disconnect()
                    }
                    break

                case .statusChange:
                    // Source settings changed, continue capturing
                    continue

                case .audio, .metadata, .none:
                    // Ignore audio, metadata, and timeouts
                    continue
                }
            }
        }
    }

    /// Generate a human-readable format description for a video frame.
    private nonisolated func formatDescription(for frame: NDIVideoFrame) -> String {
        let fourCC = frame.fourCC
        let bitDepth: String

        if fourCC == .p216 || fourCC == .pa16 {
            bitDepth = "16-bit"
        } else {
            bitDepth = "8-bit"
        }

        return "\(bitDepth) \(fourCC)"
    }
}
