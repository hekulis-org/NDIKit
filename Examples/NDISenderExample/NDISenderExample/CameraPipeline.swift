//
//  CameraPipeline.swift
//  NDISenderExample
//

import AVFoundation
import MetalKit
import NDIKit

/// Coordinates camera capture, Metal rendering, and NDI sending.
///
/// `CameraPipeline` is a thin coordinator that owns three focused subsystems:
/// - ``CameraCapture`` — AVFoundation session and sample buffer delivery.
/// - ``CameraMetalRenderer`` — Metal compute/render pipeline and display.
/// - ``NDIFrameSender`` — NDI sender lifecycle and frame transmission.
///
/// It wires them together so that the render loop can pull frames from
/// capture and push completed GPU buffers to NDI without any of the three
/// subsystems knowing about each other directly.
final class CameraPipeline {

    /// The camera capture subsystem.
    let capture = CameraCapture()

    /// The Metal renderer (also serves as the `MTKViewDelegate`).
    let renderer: CameraMetalRenderer

    /// The NDI frame sender.
    let sender = NDIFrameSender()

    /// Reports pipeline errors.
    var onError: ((String) -> Void)? {
        didSet {
            capture.onError = onError
            renderer.onError = onError
        }
    }

    /// Creates a pipeline bound to the provided Metal view.
    ///
    /// Initializes all three subsystems and wires the data-flow callbacks
    /// between them.
    ///
    /// - Parameter view: The `MTKView` to render into.
    /// - Returns: A configured pipeline, or `nil` if Metal initialization failed.
    init?(view: MTKView) {
        guard let renderer = CameraMetalRenderer(view: view) else {
            return nil
        }
        self.renderer = renderer

        // Wire the renderer to pull frames from capture.
        let capture = self.capture
        renderer.fetchFrame = { [weak capture] in
            capture?.consumePendingFrame()
        }

        // Wire the renderer to push completed frames to NDI.
        let sender = self.sender
        renderer.sendNDIFrame = { [weak sender] buffer, width, height, bytesPerRow in
            sender?.sendFrame(buffer: buffer, width: width, height: height, bytesPerRow: bytesPerRow)
        }

        // Wire the renderer to update capture orientation.
        renderer.updateRotation = { [weak capture] view in
            capture?.updateVideoRotation(for: view)
        }
    }

    /// Starts capture and NDI transmission with the provided configuration.
    ///
    /// - Parameters:
    ///   - configuration: The sender configuration containing camera, resolution,
    ///     frame rate, and NDI settings.
    ///   - camera: The `AVCaptureDevice` to capture from.
    func start(configuration: SenderConfiguration, camera: AVCaptureDevice) {
        capture.setStreaming(true)

        if let frameRate = capture.setupSession(configuration: configuration, camera: camera) {
            sender.setFrameRate(frameRate)
        }

        guard sender.start(configuration: configuration.ndiConfiguration) else {
            onError?("Failed to create NDI sender.")
            capture.setStreaming(false)
            return
        }

        capture.startSession()
    }

    /// Stops capture and tears down the active NDI sender.
    func stop() {
        capture.setStreaming(false)
        sender.stop()
        capture.stopSession()
    }
}
