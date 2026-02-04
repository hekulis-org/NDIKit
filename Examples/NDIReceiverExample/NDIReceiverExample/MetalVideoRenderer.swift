//
//  MetalVideoRenderer.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import Metal
import MetalKit
import NDIKit
import os

/// Renders NDI frames using Metal and provides them to an MTKView.
final class MetalVideoRenderer: NSObject, MTKViewDelegate, NDIFrameConsumer {
    /// Supported compute pipelines keyed by input format.
    private enum PipelineKind: CaseIterable {
        case bgra
        case rgba
        case uyvy
        case p216
    }

    /// Parameters passed to conversion compute shaders.
    private struct ConversionParams {
        var width: UInt32
        var height: UInt32
        var bytesPerRow: UInt32
        var uvPlaneOffset: UInt32
        var flags: UInt32
    }

    /// Tracks a frame and its backing buffer in flight on the GPU.
    private struct InFlightFrame {
        let frame: NDIVideoFrame
        let buffer: MTLBuffer
        let width: Int
        let height: Int
        let aspect: Double
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let renderPipeline: MTLRenderPipelineState
    private let computePipelines: [PipelineKind: MTLComputePipelineState]
    private let samplerState: MTLSamplerState
    private let maxInFlightFrames = 3
    private let inFlightSemaphore: DispatchSemaphore
    private var inFlightIndex = 0
    private var inFlightFrames: [InFlightFrame?]
    private var textureCache: [MTLTexture] = []
    private var textureSize = MTLSize(width: 0, height: 0, depth: 1)
    private var lastTexture: MTLTexture?
    private var lastFrameInfo: (width: Int, height: Int, aspect: Double)?
    private let pendingFrameLock = OSAllocatedUnfairLock<NDIVideoFrame?>(initialState: nil)
    private weak var view: MTKView?

    /// Creates a renderer bound to the provided Metal view.
    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("MetalVideoRenderer: No Metal device available")
            return nil
        }
        guard device.supportsFamily(.metal4) else {
            print("MetalVideoRenderer: Metal 4 not supported on this device")
            return nil
        }
        guard let commandQueue = device.makeCommandQueue() else {
            print("MetalVideoRenderer: Failed to create command queue")
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            print("MetalVideoRenderer: Failed to create default Metal library")
            return nil
        }

        do {
            guard let vertexFunction = library.makeFunction(name: "passthroughVertex"),
                  let fragmentFunction = library.makeFunction(name: "passthroughFragment") else {
                print("MetalVideoRenderer: Missing render shader functions")
                return nil
            }

            let renderDescriptor = MTLRenderPipelineDescriptor()
            renderDescriptor.vertexFunction = vertexFunction
            renderDescriptor.fragmentFunction = fragmentFunction
            renderDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

            let renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)

            guard let bgraFunction = library.makeFunction(name: "bgra_to_bgra"),
                  let rgbaFunction = library.makeFunction(name: "rgba_to_bgra"),
                  let uyvyFunction = library.makeFunction(name: "uyvy_to_bgra"),
                  let p216Function = library.makeFunction(name: "p216_to_bgra") else {
                print("MetalVideoRenderer: Missing compute shader functions")
                return nil
            }

            let computePipelines: [PipelineKind: MTLComputePipelineState] = [
                .bgra: try device.makeComputePipelineState(function: bgraFunction),
                .rgba: try device.makeComputePipelineState(function: rgbaFunction),
                .uyvy: try device.makeComputePipelineState(function: uyvyFunction),
                .p216: try device.makeComputePipelineState(function: p216Function)
            ]

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge

            guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else {
                print("MetalVideoRenderer: Failed to create sampler state")
                return nil
            }

            self.device = device
            self.commandQueue = commandQueue
            self.renderPipeline = renderPipeline
            self.computePipelines = computePipelines
            self.samplerState = samplerState
        } catch {
            print("MetalVideoRenderer: Pipeline creation failed: \(error)")
            return nil
        }

        self.inFlightSemaphore = DispatchSemaphore(value: maxInFlightFrames)
        self.inFlightFrames = Array(repeating: nil, count: maxInFlightFrames)
        self.view = view

        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.preferredFramesPerSecond = 60
    }

    /// Accepts a new NDI frame and schedules a draw.
    func enqueue(_ frame: NDIVideoFrame) {
        pendingFrameLock.withLock { $0 = frame }
        if let view {
            Task { @MainActor [view] in
                view.setNeedsDisplay(view.bounds)
            }
        }
    }

    @MainActor
    /// Drains any queued frames and resets GPU state.
    func drain() {
        pendingFrameLock.withLock { $0 = nil }

        for _ in 0..<maxInFlightFrames {
            inFlightSemaphore.wait()
        }

        inFlightFrames = Array(repeating: nil, count: maxInFlightFrames)
        lastTexture = nil
        lastFrameInfo = nil

        for _ in 0..<maxInFlightFrames {
            inFlightSemaphore.signal()
        }
    }

    /// Responds to drawable size changes (unused).
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// Renders the latest available frame into the drawable.
    func draw(in view: MTKView) {
        inFlightSemaphore.wait()
        var didSchedule = false
        let frameIndex = inFlightIndex
        defer {
            if !didSchedule {
                inFlightSemaphore.signal()
            } else {
                inFlightIndex = (inFlightIndex + 1) % maxInFlightFrames
            }
        }

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        let pendingFrame: NDIVideoFrame? = pendingFrameLock.withLock { frame in
            let value = frame
            frame = nil
            return value
        }

        let outputTexture: MTLTexture
        let frameInfo: (width: Int, height: Int, aspect: Double)

        if let pendingFrame {
            guard let pipelineKind = pipelineKind(for: pendingFrame.fourCC),
                  let pipeline = computePipelines[pipelineKind] else {
                print("MetalVideoRenderer: Unsupported format \(pendingFrame.fourCC)")
                return
            }

            guard let buffer = makeBuffer(from: pendingFrame) else {
                return
            }

            let width = pendingFrame.width
            let height = pendingFrame.height
            let aspect = pendingFrame.aspectRatio > 0 ? Double(pendingFrame.aspectRatio) : Double(width) / Double(height)

            guard let output = ensureOutputTexture(width: width, height: height, index: frameIndex) else {
                return
            }

            outputTexture = output
            frameInfo = (width, height, aspect)

            let commandBuffer = commandQueue.makeCommandBuffer()
            guard let commandBuffer else {
                return
            }

            let inFlightFrame = InFlightFrame(frame: pendingFrame, buffer: buffer, width: width, height: height, aspect: aspect)
            inFlightFrames[frameIndex] = inFlightFrame

            var params = buildParams(for: pendingFrame)
            guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
                inFlightFrames[frameIndex] = nil
                return
            }
            computeEncoder.setComputePipelineState(pipeline)
            computeEncoder.setBuffer(buffer, offset: 0, index: 0)
            computeEncoder.setBytes(&params, length: MemoryLayout<ConversionParams>.stride, index: 1)
            computeEncoder.setTexture(outputTexture, index: 0)

            let threadExecutionWidth = pipeline.threadExecutionWidth
            let maxThreads = pipeline.maxTotalThreadsPerThreadgroup
            let threadsPerThreadgroup = MTLSize(
                width: threadExecutionWidth,
                height: max(1, maxThreads / threadExecutionWidth),
                depth: 1
            )
            let threadsPerGrid = MTLSize(width: width, height: height, depth: 1)
            computeEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
            computeEncoder.endEncoding()

            encodeRenderPass(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                outputTexture: outputTexture,
                drawable: drawable,
                frameInfo: frameInfo
            )

            commandBuffer.addCompletedHandler { _ in
                self.inFlightFrames[frameIndex] = nil
                self.inFlightSemaphore.signal()
            }

            didSchedule = true
            commandBuffer.commit()
            lastTexture = outputTexture
            lastFrameInfo = frameInfo
        } else if let lastTexture, let lastFrameInfo {
            outputTexture = lastTexture
            frameInfo = lastFrameInfo

            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                return
            }

            encodeRenderPass(
                commandBuffer: commandBuffer,
                renderPassDescriptor: renderPassDescriptor,
                outputTexture: outputTexture,
                drawable: drawable,
                frameInfo: frameInfo
            )

            commandBuffer.addCompletedHandler { _ in
                self.inFlightSemaphore.signal()
            }

            didSchedule = true
            commandBuffer.commit()
        }

    }

    /// Maps a FourCC to the matching compute pipeline.
    private func pipelineKind(for fourCC: FourCC) -> PipelineKind? {
        if fourCC == .bgra || fourCC == .bgrx {
            return .bgra
        }
        if fourCC == .rgba || fourCC == .rgbx {
            return .rgba
        }
        if fourCC == .uyvy {
            return .uyvy
        }
        if fourCC == .p216 {
            return .p216
        }
        return nil
    }

    /// Builds compute parameters for a given frame.
    private func buildParams(for frame: NDIVideoFrame) -> ConversionParams {
        let hasAlpha: Bool
        if frame.fourCC == .bgra || frame.fourCC == .rgba {
            hasAlpha = true
        } else {
            hasAlpha = false
        }

        let uvPlaneOffset = frame.fourCC == .p216 ? UInt32(frame.lineStride * frame.height) : 0
        let flags: UInt32 = hasAlpha ? 1 : 0

        return ConversionParams(
            width: UInt32(frame.width),
            height: UInt32(frame.height),
            bytesPerRow: UInt32(frame.lineStride),
            uvPlaneOffset: uvPlaneOffset,
            flags: flags
        )
    }

    /// Allocates and copies frame data into a shared Metal buffer.
    private func makeBuffer(from frame: NDIVideoFrame) -> MTLBuffer? {
        guard let baseAddress = frame.data?.baseAddress else {
            return nil
        }
        let length = dataLength(for: frame)
        let mutableBase = UnsafeMutableRawPointer(mutating: baseAddress)
        return device.makeBuffer(bytesNoCopy: mutableBase, length: length, options: .storageModeShared, deallocator: nil)
    }

    /// Computes the byte length for a frame buffer.
    private func dataLength(for frame: NDIVideoFrame) -> Int {
        if frame.fourCC == .p216 {
            return frame.lineStride * frame.height * 2
        }
        return frame.lineStride * frame.height
    }

    /// Ensures a reusable output texture exists for the given size.
    private func ensureOutputTexture(width: Int, height: Int, index: Int) -> MTLTexture? {
        if textureSize.width != width || textureSize.height != height || textureCache.count != maxInFlightFrames {
            textureSize = MTLSize(width: width, height: height, depth: 1)
            textureCache = (0..<maxInFlightFrames).compactMap { _ in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .private
                return device.makeTexture(descriptor: descriptor)
            }
        }

        guard index < textureCache.count else { return nil }
        return textureCache[index]
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
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
    }

    /// Fits the frame into the view while preserving aspect ratio.
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
}
