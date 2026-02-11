//
//  CameraCapture.swift
//  NDISenderExample
//

import AVFoundation
import MetalKit
import os
import UIKit

/// Manages AVFoundation camera capture and delivers the latest frame to consumers.
///
/// `CameraCapture` owns the `AVCaptureSession`, handles the sample buffer
/// delegate callback, and stores the most recent camera frame for the render
/// loop to consume via ``consumePendingFrame()``.
///
/// Orientation is handled by observing `UIDevice.orientationDidChangeNotification`
/// and setting `videoRotationAngle` on the capture connection so that
/// AVFoundation delivers pre-rotated pixel buffers. The front camera
/// additionally enables `isVideoMirrored` for the expected selfie-mirror effect.
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
    private var orientationObserver: NSObjectProtocol?

    /// Reports capture errors.
    var onError: ((String) -> Void)?

    deinit {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Session Lifecycle

    /// Configures a new capture session with the specified camera and settings.
    ///
    /// Tears down any existing session before creating a new one. Sets the
    /// initial rotation angle to match the current device orientation and
    /// begins observing orientation changes.
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

            // Front camera: mirror horizontally for the expected selfie view.
            // Without this, rotation + the front sensor's native flip combine
            // to produce an upside-down image.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (camera.position == .front)
            }

            // Set the initial rotation angle immediately so the very first
            // frames are correctly oriented. Do not wait for the render loop.
            let angle = rotationAngle(for: UIDevice.current.orientation)
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }

            // Observe device orientation changes to keep the rotation in sync.
            startObservingOrientation()
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
        // Ensure we receive orientation change notifications.
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

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
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
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

    /// Begins observing device orientation change notifications.
    ///
    /// When the device rotates, the capture connection's `videoRotationAngle`
    /// is updated to match, so AVFoundation delivers pre-rotated buffers.
    private func startObservingOrientation() {
        // Remove any previous observer.
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyCurrentDeviceOrientation()
        }
    }

    /// Reads the current device orientation and updates the capture connection.
    private func applyCurrentDeviceOrientation() {
        guard let connection = videoConnection else { return }

        let deviceOrientation = UIDevice.current.orientation
        let angle = rotationAngle(for: deviceOrientation)
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// Maps a device orientation to the capture connection rotation angle.
    ///
    /// The angle tells AVFoundation how many degrees clockwise to rotate
    /// the sensor output so it appears upright for the given orientation.
    /// These values are the same for both front and back cameras —
    /// front-camera mirroring is handled separately via `isVideoMirrored`.
    ///
    /// - Parameter orientation: The current device orientation.
    /// - Returns: The rotation angle in degrees, or `nil` for non-video
    ///   orientations (face up, face down, unknown).
    private func rotationAngle(for orientation: UIDeviceOrientation) -> Double {
        switch orientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            // Device rotated left → home button on right → content rotated clockwise.
            return 0
        case .landscapeRight:
            // Device rotated right → home button on left → content rotated counter-clockwise.
            return 180
        case .unknown, .faceUp, .faceDown:
            // Non-spatial orientations: keep the current connection angle.
            if let angle = videoConnection?.videoRotationAngle {
                return Double(angle)
            }
            return 90
        @unknown default:
            if let angle = videoConnection?.videoRotationAngle {
                return Double(angle)
            }
            return 90
        }
    }
}
