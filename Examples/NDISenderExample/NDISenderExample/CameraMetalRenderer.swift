//
//  CameraMetalRenderer.swift
//  NDISenderExample
//

import AVFoundation
import Metal
import MetalKit

/// Renders camera frames using Metal and drives the display/send pipeline.
///
/// `CameraMetalRenderer` owns the Metal device, command queue, compute and
/// render pipelines, frame buffer ring, and the in-flight semaphore. It
/// implements `MTKViewDelegate` and is driven by the display link.
///
/// The renderer does not own camera capture or NDI sending directly. Instead
/// it communicates with those subsystems through closures:
/// - ``fetchFrame`` — pulls the latest camera frame.
/// - ``sendNDIFrame`` — pushes a completed GPU buffer to NDI.
final class CameraMetalRenderer: NSObject, MTKViewDelegate {

    /// Parameters passed to the NV12-to-UYVY compute shader.
    private struct ConversionParams {
        var width: UInt32
        var height: UInt32
        var bytesPerRow: UInt32
    }

    /// Backing storage for a single in-flight frame.
    private struct FrameBuffer {
        /// Shared UYVY data readable by the CPU for NDI transmission.
        let ndiBuffer: MTLBuffer
        /// Private BGRA texture for on-screen preview (GPU-only).
        let displayTexture: MTLTexture
        /// Line stride for the UYVY buffer, in bytes.
        let ndiBytesPerRow: Int
        /// Frame width in pixels.
        let width: Int
        /// Frame height in pixels.
        let height: Int
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let inFlightSemaphore: DispatchSemaphore
    private let maxInFlightFrames = 3

    private var textureCache: CVMetalTextureCache?
    private var frameBuffers: [FrameBuffer] = []
    private var frameIndex = 0
    private var lastTexture: MTLTexture?
    private var lastFrameInfo: (width: Int, height: Int, aspect: Double)?

    // MARK: - Callbacks

    /// Pulls the latest pending camera frame.
    ///
    /// Set by the coordinator to bridge to ``CameraCapture/consumePendingFrame()``.
    var fetchFrame: (() -> CameraCapture.PendingFrame?)?

    /// Sends a completed UYVY buffer to NDI.
    ///
    /// Called from the Metal command buffer completion handler.
    /// Parameters are: (buffer, width, height, bytesPerRow).
    var sendNDIFrame: ((MTLBuffer, Int, Int, Int) -> Void)?

    /// Reports renderer errors.
    var onError: ((String) -> Void)?

    // MARK: - Initialization

    /// Creates a renderer bound to the provided Metal view.
    ///
    /// Configures the Metal device, command queue, compute pipeline
    /// (NV12→UYVY conversion), render pipeline (full-screen quad), sampler,
    /// and texture cache.
    ///
    /// - Parameter view: The `MTKView` to render into.
    /// - Returns: A configured renderer, or `nil` if Metal setup failed.
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

    // MARK: - MTKViewDelegate

    /// Responds to drawable size changes.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Renders the latest camera frame and schedules an NDI send on completion.
    ///
    /// The draw loop follows this sequence:
    /// 1. Wait on the in-flight semaphore (backpressure).
    /// 2. Fetch the latest pending frame from ``fetchFrame``.
    /// 3. Create Metal textures from the NV12 pixel buffer planes.
    /// 4. Encode a compute pass (NV12→UYVY + BGRA display).
    /// 5. Encode a render pass (display texture → drawable).
    /// 6. On GPU completion, send the UYVY buffer via ``sendNDIFrame``
    ///    and signal the semaphore.
    func draw(in view: MTKView) {
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

        let pendingFrame = fetchFrame?()

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
                // Each thread processes a 2-pixel macro-pixel.
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
                self.sendNDIFrame?(
                    frameBuffer.ndiBuffer,
                    frameBuffer.width,
                    frameBuffer.height,
                    frameBuffer.ndiBytesPerRow
                )
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

    // MARK: - Metal Helpers

    /// Ensures a ring of frame buffers exists at the requested resolution.
    ///
    /// Each buffer contains a shared UYVY buffer for NDI and a private BGRA
    /// texture for display. Buffers are recreated when the resolution changes.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - index: The ring buffer index to return.
    /// - Returns: The frame buffer at the given index, or `nil` if allocation
    ///   failed.
    private func ensureFrameBuffer(width: Int, height: Int, index: Int) -> FrameBuffer? {
        if frameBuffers.first?.width != width || frameBuffers.first?.height != height || frameBuffers.count != maxInFlightFrames {
            frameBuffers = (0..<maxInFlightFrames).compactMap { _ in
                // UYVY: 2 bytes per pixel.
                let ndiBytesPerRow = align(value: width * 2, alignment: 64)
                guard let ndiBuffer = device.makeBuffer(length: ndiBytesPerRow * height, options: .storageModeShared) else {
                    return nil
                }

                // Display texture: BGRA, GPU-only access.
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
    ///
    /// - Parameters:
    ///   - pixelBuffer: The source `CVPixelBuffer`.
    ///   - pixelFormat: The Metal pixel format for the texture view.
    ///   - planeIndex: The plane index within the pixel buffer.
    /// - Returns: A Metal texture backed by the pixel buffer plane, or `nil`
    ///   on failure.
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

    /// Encodes a full-screen textured render pass with aspect-ratio-correct viewport.
    ///
    /// - Parameters:
    ///   - commandBuffer: The command buffer to encode into.
    ///   - renderPassDescriptor: The render pass descriptor from the view.
    ///   - outputTexture: The BGRA texture to sample.
    ///   - drawable: The drawable to present.
    ///   - frameInfo: The frame dimensions and aspect ratio.
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

    /// Computes a viewport that fits the video frame into the view while
    /// preserving the aspect ratio (letterbox or pillarbox).
    ///
    /// - Parameters:
    ///   - viewSize: The size of the destination view in pixels.
    ///   - frameSize: The size of the source video frame in pixels.
    ///   - aspect: The target aspect ratio.
    /// - Returns: An `MTLViewport` that centers the content with correct aspect.
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
    ///
    /// - Parameters:
    ///   - value: The value to align.
    ///   - alignment: The alignment boundary (must be a power of two).
    /// - Returns: The smallest multiple of `alignment` that is ≥ `value`.
    private func align(value: Int, alignment: Int) -> Int {
        let mask = alignment - 1
        return (value + mask) & ~mask
    }
}
