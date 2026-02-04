//
//  CameraSenderViewModel.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import AVFoundation
import Observation

/// Manages camera capture and NDI streaming state.
@MainActor
@Observable
final class CameraSenderViewModel {

    // MARK: - Published State

    var configuration = SenderConfiguration()
    private(set) var isStreaming = false
    private(set) var errorMessage: String?

    // MARK: - Private State

    private var renderer: CameraSenderRenderer?

    // MARK: - Renderer Wiring

    func setRenderer(_ renderer: CameraSenderRenderer?) {
        self.renderer = renderer
        renderer?.onError = { [weak self] message in
            Task { @MainActor in
                self?.errorMessage = message
                self?.isStreaming = false
            }
        }
    }

    func setErrorMessage(_ message: String?) {
        errorMessage = message
    }

    // MARK: - Streaming Control

    func startStreaming() {
        Task {
            guard await ensureCameraAccess() else {
                errorMessage = "Camera access is required to stream."
                return
            }

            errorMessage = nil
            guard let renderer else {
                errorMessage = "Failed to initialize Metal renderer."
                return
            }
            renderer.start(configuration: configuration)
            isStreaming = true
        }
    }

    func stopStreaming() {
        renderer?.stop()
        isStreaming = false
    }

    // MARK: - Permissions

    private func ensureCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
