//
//  NDIFrameSender.swift
//  NDISenderExample
//

import Metal
import NDIKit
import os

/// Manages the NDI sender lifecycle and transmits completed video frames.
///
/// `NDIFrameSender` owns the ``NDISender`` instance behind a lock so that
/// the Metal completion handler can safely call ``sendFrame(buffer:width:height:bytesPerRow:)``
/// from any thread.
final class NDIFrameSender {

    private let senderLock = OSAllocatedUnfairLock<NDISender?>(initialState: nil)
    private var frameRate: (numerator: Int, denominator: Int) = (30000, 1001)

    // MARK: - Lifecycle

    /// Creates an NDI sender with the given configuration and begins accepting frames.
    ///
    /// - Parameter configuration: The NDI sender configuration (name, groups,
    ///   clocking options).
    /// - Returns: `true` if the sender was created successfully, `false` otherwise.
    @discardableResult
    func start(configuration: NDISender.Configuration) -> Bool {
        guard let sender = NDISender(configuration: configuration) else {
            return false
        }
        senderLock.withLock { $0 = sender }
        return true
    }

    /// Tears down the active NDI sender.
    ///
    /// Any in-flight calls to ``sendFrame(buffer:width:height:bytesPerRow:)``
    /// that race with this method will safely observe `nil` and skip the send.
    func stop() {
        senderLock.withLock { $0 = nil }
    }

    // MARK: - Configuration

    /// Updates the frame rate used for subsequent ``sendFrame(buffer:width:height:bytesPerRow:)`` calls.
    ///
    /// - Parameter rate: The frame rate as a fraction (numerator / denominator),
    ///   e.g. `(30000, 1001)` for 29.97 fps.
    func setFrameRate(_ rate: (numerator: Int, denominator: Int)) {
        frameRate = rate
    }

    // MARK: - Sending

    /// Sends a completed UYVY video frame over NDI.
    ///
    /// This method is safe to call from the Metal command buffer completion
    /// handler on any thread. If the sender has been stopped, the call is
    /// silently ignored.
    ///
    /// - Parameters:
    ///   - buffer: The Metal buffer containing UYVY pixel data
    ///     (`.storageModeShared`).
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - bytesPerRow: The line stride of the UYVY buffer, in bytes.
    func sendFrame(buffer: MTLBuffer, width: Int, height: Int, bytesPerRow: Int) {
        guard let sender = senderLock.withLock({ $0 }) else { return }

        let pointer = buffer.contents().assumingMemoryBound(to: UInt8.self)
        sender.sendVideo(
            width: width,
            height: height,
            fourCC: .uyvy,
            frameRate: frameRate,
            aspectRatio: Float(width) / Float(height),
            formatType: .progressive,
            data: pointer,
            lineStride: bytesPerRow
        )
    }
}
