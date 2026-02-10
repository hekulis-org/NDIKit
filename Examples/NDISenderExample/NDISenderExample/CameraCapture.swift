//
//  CameraCapture.swift
//  NDISenderExample
//

import AVFoundation
import MetalKit
import os

/// Manages AVFoundation camera capture and delivers the latest frame to consumers.
///
/// `CameraCapture` owns the `AVCaptureSession`, handles the sample buffer
/// delegate callback, and stores the most recent camera frame for the render
/// loop to consume via ``consumePendingFrame()``.
///
/// - Note: AVFoundation requires a non-nil `DispatchQueue` for
///   `AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:)`.
///   This is the only use of GCD in this type.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// The most recent camera frame awaiting consumption by the render loop.
    struct PendingFrame {
        /// The pixel buffer containing NV12 image data.
        let pixelBuffer: CVPixelBuffer
        /// The presentation timestamp of the sample.
        let timestamp: CMTime
    }

    /// Wraps the capture session so it can be passed into a detached task.
    nonisolated private struct SessionHandle: @unchecked Sendable {
        let session: AVCaptureSession?
    }

    // AVFoundation requires a non-nil DispatchQueue for sample buffer callbacks.
    private let captureQueue = DispatchQueue(label: "com.ndikit.sender.capture")

    private let pendingFrameLock = OSAllocatedUnfairLock<PendingFrame?>(initialState: nil)
    private let streamingLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    private var session: AVCaptureSession?
    private weak var videoConnection: AVCaptureConnection?
    private var lastRotationAngle: Double = 0

    /// Reports capture errors.
    var onError: ((String) -> Void)?

    // MARK: - Session Lifecycle

    /// Configures a new capture session with the specified camera and settings.
    ///
    /// Tears down any existing session before creating a new one.
    ///
    /// - Parameters:
    ///   - configuration: The sender configuration containing resolution and
    ///     frame rate settings.
    ///   - camera: The `AVCaptureDevice` to capture from.
    /// - Returns: The configured NDI frame rate fraction, or `nil` if setup failed.
    @discardableResult
    func setupSession(
        configuration: SenderConfiguration,
        camera: AVCaptureDevice
    ) -> (numerator: Int, denominator: Int)? {
        // Tear down existing session if any.
        if let existingSession = session {
            existingSession.stopRunning()
            self.session = nil
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Set resolution preset.
        let preset = configuration.resolution.sessionPreset
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        var frameRate: (numerator: Int, denominator: Int)?

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            // Configure frame rate.
            try camera.lockForConfiguration()
            let targetDuration = configuration.frameRate.cmTime

            // Find a format that supports the desired frame rate.
            let desiredFPS = Float64(configuration.frameRate.rawValue)
            for format in camera.formats {
                let ranges = format.videoSupportedFrameRateRanges
                for range in ranges where range.minFrameRate <= desiredFPS && range.maxFrameRate >= desiredFPS {
                    camera.activeFormat = format
                    break
                }
            }

            camera.activeVideoMinFrameDuration = targetDuration
            camera.activeVideoMaxFrameDuration = targetDuration
            camera.unlockForConfiguration()

            frameRate = configuration.frameRate.ndiFrameRate
        } catch {
            session.commitConfiguration()
            onError?("Failed to configure camera: \(error.localizedDescription)")
            return nil
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        if let connection = output.connection(with: .video) {
            videoConnection = connection
        }

        session.commitConfiguration()
        self.session = session
        return frameRate
    }

    /// Starts the capture session on a background thread.
    ///
    /// Uses `Task.detached` to avoid blocking the main thread, as recommended
    /// for `AVCaptureSession.startRunning()`.
    func startSession() {
        let handle = SessionHandle(session: session)
        Task.detached(priority: .userInitiated) {
            handle.session?.startRunning()
        }
    }

    /// Stops the capture session on a background thread.
    ///
    /// Uses `Task.detached` to avoid blocking the main thread, as recommended
    /// for `AVCaptureSession.stopRunning()`.
    func stopSession() {
        let handle = SessionHandle(session: session)
        Task.detached(priority: .userInitiated) {
            handle.session?.stopRunning()
        }
    }

    // MARK: - Streaming State

    /// Sets whether the capture pipeline is actively streaming.
    ///
    /// When `false`, incoming camera frames are silently discarded.
    ///
    /// - Parameter streaming: `true` to accept frames, `false` to discard.
    func setStreaming(_ streaming: Bool) {
        streamingLock.withLock { $0 = streaming }
    }

    // MARK: - Frame Access

    /// Atomically consumes and returns the most recent pending frame.
    ///
    /// The pending frame slot is cleared after this call. If no frame is
    /// available, returns `nil`.
    ///
    /// - Returns: The latest camera frame, or `nil` if none is pending.
    func consumePendingFrame() -> PendingFrame? {
        pendingFrameLock.withLock { frame in
            let value = frame
            frame = nil
            return value
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    /// Receives camera frames from AVFoundation and stores the latest for rendering.
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard streamingLock.withLock({ $0 }) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let pending = PendingFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        pendingFrameLock.withLock { current in
            current = pending
        }
    }

    // MARK: - Orientation

    /// Updates the capture connection rotation to match the current interface orientation.
    ///
    /// - Parameter view: The `MTKView` whose window scene provides the current
    ///   interface orientation.
    func updateVideoRotation(for view: MTKView) {
        guard let connection = videoConnection else { return }
        let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
        let angle = rotationAngle(for: orientation)
        if angle != lastRotationAngle, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            lastRotationAngle = angle
        }
    }

    /// Maps an interface orientation to a capture rotation angle in degrees.
    ///
    /// - Parameter orientation: The current interface orientation, or `nil`.
    /// - Returns: The rotation angle to apply to the capture connection.
    private func rotationAngle(for orientation: UIInterfaceOrientation?) -> Double {
        switch orientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 180
        case .landscapeRight:
            return 0
        default:
            return lastRotationAngle
        }
    }
}
