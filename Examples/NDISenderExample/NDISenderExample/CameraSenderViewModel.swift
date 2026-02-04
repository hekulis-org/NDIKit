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
    private(set) var availableCameras: [CameraDevice] = []

    // MARK: - Private State

    private var renderer: CameraSenderRenderer?

    // MARK: - Initialization

    init() {
        discoverCameras()
    }

    // MARK: - Camera Discovery

    func discoverCameras() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInUltraWideCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera
        ]

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        )

        availableCameras = discoverySession.devices.map { device in
            CameraDevice(
                id: device.uniqueID,
                name: formatCameraName(device),
                position: device.position,
                device: device
            )
        }

        // Select first camera if none selected
        if configuration.selectedCameraID == nil, let first = availableCameras.first {
            configuration.selectedCameraID = first.id
        }
    }

    private func formatCameraName(_ device: AVCaptureDevice) -> String {
        let position: String
        switch device.position {
        case .front:
            position = "Front"
        case .back:
            position = "Back"
        default:
            position = ""
        }

        // Extract lens type from localized name
        let name = device.localizedName
        if position.isEmpty {
            return name
        }
        return "\(position) - \(name)"
    }

    var selectedCamera: CameraDevice? {
        availableCameras.first { $0.id == configuration.selectedCameraID }
    }

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

            guard let camera = selectedCamera else {
                errorMessage = "No camera selected."
                return
            }

            renderer.start(configuration: configuration, camera: camera.device)
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
