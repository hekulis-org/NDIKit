//
//  CameraSenderRenderer.swift
//  NDISenderExample
//
//  Created by Ed on 04.02.26.
//

import AVFoundation
import Metal
import MetalKit
import NDIKit
import UIKit
import os

/// Renders camera frames with Metal and sends them as NDI video frames.
final class CameraSenderRenderer: NSObject, MTKViewDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Parameters passed to the NV12-to-UYVY compute shader.
    private struct ConversionParams {
        var width: UInt32
        var height: UInt32
        var bytesPerRow: UInt32
    }

    /// Backing storage for a single in-flight frame.
    private struct FrameBuffer {
        let ndiBuffer: MTLBuffer       // UYVY data for NDI (shared storage)
        let displayTexture: MTLTexture // BGRA texture for on-screen preview
        let ndiBytesPerRow: Int        // Line stride for UYVY buffer
        let width: Int
        let height: Int
    }

    /// The most recent camera frame awaiting render/send.
    private struct PendingFrame {
        let pixelBuffer: CVPixelBuffer
        let timestamp: CMTime
    }

    /// Wraps the capture session for use in detached tasks.
    nonisolated private struct SessionHandle: @unchecked Sendable {
        let session: AVCaptureSession?
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let inFlightSemaphore: DispatchSemaphore
    private let maxInFlightFrames = 3

    private let pendingFrameLock = OSAllocatedUnfairLock<PendingFrame?>(initialState: nil)
    private let senderLock = OSAllocatedUnfairLock<NDISender?>(initialState: nil)
    private let streamingLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    private var textureCache: CVMetalTextureCache?
    private var frameBuffers: [FrameBuffer] = []
    private var frameIndex = 0
    private var lastTexture: MTLTexture?
    private var lastFrameInfo: (width: Int, height: Int, aspect: Double)?
    private var frameRate: (numerator: Int, denominator: Int) = (30000, 1001)
    private var lastRotationAngle: Double = 0

    private weak var view: MTKView?
    // AVFoundation requires a non-nil DispatchQueue for sample buffer callbacks.
    private let captureQueue = DispatchQueue(label: "com.ndikit.sender.capture")
    private var session: AVCaptureSession?
    private weak var videoConnection: AVCaptureConnection?

    /// Reports renderer errors.
    var onError: ((String) -> Void)?

    /// Creates a renderer bound to the provided Metal view.
    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            return nil
        }

        guard let computeFunction = library.makeFunction(name: "nv12_to_uyvy") else {
            return nil
        }
        guard let vertexFunction = library.makeFunction(name: "cameraVertex"),
              let fragmentFunction = library.makeFunction(name: "cameraFragment") else {
            return nil
        }

        do {
            computePipeline = try device.makeComputePipelineState(function: computeFunction)

            let renderDescriptor = MTLRenderPipelineDescriptor()
            renderDescriptor.vertexFunction = vertexFunction
            renderDescriptor.fragmentFunction = fragmentFunction
            renderDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        } catch {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.samplerState = samplerState
        self.inFlightSemaphore = DispatchSemaphore(value: maxInFlightFrames)
        self.view = view

        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        var cache: CVMetalTextureCache?
        let cacheResult = CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        if cacheResult != kCVReturnSuccess {
            onError?("Failed to create Metal texture cache.")
        }
        textureCache = cache
    }

    /// Starts capture and NDI transmission with the provided configuration.
    func start(configuration: SenderConfiguration, camera: AVCaptureDevice) {
        streamingLock.withLock { $0 = true }

        setupSession(configuration: configuration, camera: camera)

        guard let sender = NDISender(configuration: configuration.ndiConfiguration) else {
            onError?("Failed to create NDI sender.")
            streamingLock.withLock { $0 = false }
            return
        }

        senderLock.withLock { $0 = sender }
        let handle = SessionHandle(session: session)
        Task.detached(priority: .userInitiated) {
            handle.session?.startRunning()
        }
    }

    /// Stops capture and tears down the active NDI sender.
    func stop() {
        streamingLock.withLock { $0 = false }
        senderLock.withLock { $0 = nil }
        let handle = SessionHandle(session: session)
        Task.detached(priority: .userInitiated) {
            handle.session?.stopRunning()
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    /// Receives camera frames and stores the latest for rendering.
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

    // MARK: - MTKViewDelegate

    /// Responds to drawable size changes (unused).
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Renders the latest camera frame and schedules an NDI send.
    func draw(in view: MTKView) {
        updateVideoRotation(for: view)
        inFlightSemaphore.wait()
        var didSchedule = false
        let bufferIndex = frameIndex
        defer {
            if !didSchedule {
                inFlightSemaphore.signal()
            } else {
                frameIndex = (frameIndex + 1) % maxInFlightFrames
            }
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let pendingFrame: PendingFrame? = pendingFrameLock.withLock { frame in
            let value = frame
            frame = nil
            return value
        }

        if let pendingFrame {
            let pixelBuffer = pendingFrame.pixelBuffer
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            guard let frameBuffer = ensureFrameBuffer(width: width, height: height, index: bufferIndex) else {
                return
            }

            guard let lumaTexture = makeTexture(from: pixelBuffer, pixelFormat: .r8Unorm, planeIndex: 0),
                  let chromaTexture = makeTexture(from: pixelBuffer, pixelFormat: .rg8Unorm, planeIndex: 1) else {
                return
            }

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(computePipeline)
                computeEncoder.setTexture(lumaTexture, index: 0)
                computeEncoder.setTexture(chromaTexture, index: 1)
                computeEncoder.setTexture(frameBuffer.displayTexture, index: 2)
                computeEncoder.setBuffer(frameBuffer.ndiBuffer, offset: 0, index: 0)

                var params = ConversionParams(
                    width: UInt32(width),
                    height: UInt32(height),
                    bytesPerRow: UInt32(frameBuffer.ndiBytesPerRow)
                )
                computeEncoder.setBytes(&params, length: MemoryLayout<ConversionParams>.stride, index: 1)

                let threadExecutionWidth = computePipeline.threadExecutionWidth
                let maxThreads = computePipeline.maxTotalThreadsPerThreadgroup
                let threadsPerThreadgroup = MTLSize(
                    width: threadExecutionWidth,
                    height: max(1, maxThreads / threadExecutionWidth),
                    depth: 1
                )
                // Each thread processes a 2-pixel macro-pixel
                let threadsPerGrid = MTLSize(width: (width + 1) / 2, height: height, depth: 1)
                computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
                computeEncoder.endEncoding()
            }

            encodeRenderPass(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                outputTexture: frameBuffer.displayTexture,
                drawable: drawable,
                frameInfo: (width: width, height: height, aspect: Double(width) / Double(height))
            )

            commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self else { return }

                if let sender = self.senderLock.withLock({ $0 }) {
                    let pointer = frameBuffer.ndiBuffer.contents().assumingMemoryBound(to: UInt8.self)
                    sender.sendVideo(
                        width: frameBuffer.width,
                        height: frameBuffer.height,
                        fourCC: .uyvy,
                        frameRate: self.frameRate,
                        aspectRatio: Float(frameBuffer.width) / Float(frameBuffer.height),
                        formatType: .progressive,
                        data: pointer,
                        lineStride: frameBuffer.ndiBytesPerRow
                    )
                }

                self.inFlightSemaphore.signal()
            }

            didSchedule = true
            commandBuffer.commit()
            lastTexture = frameBuffer.displayTexture
            lastFrameInfo = (width: width, height: height, aspect: Double(width) / Double(height))
        } else if let lastTexture, let lastFrameInfo {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            encodeRenderPass(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                outputTexture: lastTexture,
                drawable: drawable,
                frameInfo: lastFrameInfo
            )

            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.inFlightSemaphore.signal()
            }

            didSchedule = true
            commandBuffer.commit()
        }
    }

    // MARK: - Session Setup

    /// Configures the capture session with the specified camera and settings.
    private func setupSession(configuration: SenderConfiguration, camera: AVCaptureDevice) {
        // Tear down existing session if any
        if let existingSession = session {
            existingSession.stopRunning()
            self.session = nil
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Set resolution preset
        let preset = configuration.resolution.sessionPreset
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        } else if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            // Configure frame rate
            try camera.lockForConfiguration()
            let targetDuration = configuration.frameRate.cmTime

            // Find a format that supports our desired frame rate
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
            return
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
            if let view = view {
                updateVideoRotation(for: view)
            }
        }

        session.commitConfiguration()
        self.session = session
    }

    // MARK: - Metal Helpers

    /// Ensures a ring of frame buffers exists at the requested size.
    /// Each buffer contains a shared UYVY buffer for NDI and a private BGRA texture for display.
    private func ensureFrameBuffer(width: Int, height: Int, index: Int) -> FrameBuffer? {
        if frameBuffers.first?.width != width || frameBuffers.first?.height != height || frameBuffers.count != maxInFlightFrames {
            frameBuffers = (0..<maxInFlightFrames).compactMap { _ in
                // UYVY: 2 bytes per pixel
                let ndiBytesPerRow = align(value: width * 2, alignment: 64)
                guard let ndiBuffer = device.makeBuffer(length: ndiBytesPerRow * height, options: .storageModeShared) else {
                    return nil
                }

                // Display texture: BGRA, GPU-only access
                let displayDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                displayDescriptor.usage = [.shaderRead, .shaderWrite]
                displayDescriptor.storageMode = .private

                guard let displayTexture = device.makeTexture(descriptor: displayDescriptor) else {
                    return nil
                }

                return FrameBuffer(ndiBuffer: ndiBuffer, displayTexture: displayTexture, ndiBytesPerRow: ndiBytesPerRow, width: width, height: height)
            }
        }

        guard index < frameBuffers.count else { return nil }
        return frameBuffers[index]
    }

    /// Creates a Metal texture view of a pixel buffer plane.
    private func makeTexture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> MTLTexture? {
        guard let textureCache else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)

        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &cvTexture
        )

        guard result == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    /// Encodes a textured full-screen render pass.
    private func encodeRenderPass(
        commandBuffer: MTLCommandBuffer,
        renderPassDescriptor: MTLRenderPassDescriptor,
        outputTexture: MTLTexture,
        drawable: MTLDrawable,
        frameInfo: (width: Int, height: Int, aspect: Double)
    ) {
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let viewWidth = CGFloat(renderPassDescriptor.colorAttachments[0].texture?.width ?? frameInfo.width)
        let viewHeight = CGFloat(renderPassDescriptor.colorAttachments[0].texture?.height ?? frameInfo.height)
        let viewport = fitViewport(
            viewSize: CGSize(width: viewWidth, height: viewHeight),
            frameSize: CGSize(width: CGFloat(frameInfo.width), height: CGFloat(frameInfo.height)),
            aspect: frameInfo.aspect
        )

        renderEncoder.setViewport(viewport)
        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setFragmentTexture(outputTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
    }

    /// Fits the video into the view while preserving aspect ratio.
    private func fitViewport(viewSize: CGSize, frameSize: CGSize, aspect: Double) -> MTLViewport {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return MTLViewport(originX: 0, originY: 0, width: 0, height: 0, znear: 0, zfar: 1)
        }

        let viewAspect = Double(viewSize.width / viewSize.height)
        let targetAspect = aspect

        if targetAspect > viewAspect {
            let width = viewSize.width
            let height = width / targetAspect
            let originY = (viewSize.height - height) * 0.5
            return MTLViewport(originX: 0, originY: originY, width: width, height: height, znear: 0, zfar: 1)
        } else {
            let height = viewSize.height
            let width = height * targetAspect
            let originX = (viewSize.width - width) * 0.5
            return MTLViewport(originX: originX, originY: 0, width: width, height: height, znear: 0, zfar: 1)
        }
    }

    /// Aligns a value up to the requested byte alignment.
    private func align(value: Int, alignment: Int) -> Int {
        let mask = alignment - 1
        return (value + mask) & ~mask
    }

    // MARK: - Orientation

    /// Updates the capture connection rotation to match the current interface orientation.
    private func updateVideoRotation(for view: MTKView) {
        guard let connection = videoConnection else { return }
        let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation
        let angle = rotationAngle(for: orientation)
        if angle != lastRotationAngle, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
            lastRotationAngle = angle
        }
    }

    /// Maps interface orientation to a capture rotation angle.
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
