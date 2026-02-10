//
//  NDIVideoFormatConverter.swift
//  NDIKitMetal
//
//  Vends Metal compute pipeline states for converting between NDI wire
//  formats and Metal textures. Does not create command buffers, encode
//  commands, or manage textures — the client owns its own Metal pipeline.
//

import Metal
import NDIKit

/// Loads and caches Metal compute pipelines for converting between NDI wire
/// formats and Metal textures.
///
/// `NDIVideoFormatConverter` is a lightweight, `Sendable` value type that
/// you create once per `MTLDevice`. It does **not** allocate command buffers,
/// encode commands, or manage textures — those remain the responsibility of
/// your rendering code. The converter only provides ready-to-use pipeline
/// states and helpers for thread dispatch sizing.
///
/// ```swift
/// let converter = try NDIVideoFormatConverter(device: device)
///
/// // Decode an incoming NDI UYVY frame:
/// if let pipeline = converter.decodePipeline(for: frame.fourCC) {
///     let params = NDIConversionParams.decode(frame: frame)
///     let grid = converter.decodeThreadsPerGrid(width: frame.width, height: frame.height)
///     let group = converter.threadsPerThreadgroup(for: pipeline)
///     // ... encode your compute pass ...
/// }
///
/// // Encode a BGRA texture to UYVY for NDI sending:
/// if let pipeline = converter.encodePipeline(for: .bgra) {
///     let params = NDIConversionParams.encode(width: width, height: height, uyvyBytesPerRow: stride)
///     let grid = converter.encodeThreadsPerGrid(width: width, height: height)
///     let group = converter.threadsPerThreadgroup(for: pipeline)
///     // ... encode your compute pass ...
/// }
/// ```
public struct NDIVideoFormatConverter: Sendable {

    // MARK: - Decode Pipelines

    private let bgraPipeline: MTLComputePipelineState
    private let rgbaPipeline: MTLComputePipelineState
    private let uyvyPipeline: MTLComputePipelineState
    private let p216Pipeline: MTLComputePipelineState

    // MARK: - Encode Pipelines

    private let nv12ToUyvyPipeline: MTLComputePipelineState
    private let bgraToUyvyPipeline: MTLComputePipelineState
    private let rgbafToUyvyPipeline: MTLComputePipelineState

    // MARK: - Initialization

    /// Creates a converter by loading the NDIKitMetal shader library from the
    /// framework bundle.
    ///
    /// - Parameter device: The Metal device to compile pipelines against.
    /// - Throws: An error if the shader library or any pipeline state cannot
    ///   be created.
    public init(device: MTLDevice) throws {
        let library = try Self.loadLibrary(device: device)

        // Decode pipelines
        bgraPipeline = try Self.makePipeline(device: device, library: library, name: "ndi_bgra_to_bgra")
        rgbaPipeline = try Self.makePipeline(device: device, library: library, name: "ndi_rgba_to_bgra")
        uyvyPipeline = try Self.makePipeline(device: device, library: library, name: "ndi_uyvy_to_bgra")
        p216Pipeline = try Self.makePipeline(device: device, library: library, name: "ndi_p216_to_bgra")

        // Encode pipelines
        nv12ToUyvyPipeline = try Self.makePipeline(device: device, library: library, name: "ndi_nv12_to_uyvy")
        bgraToUyvyPipeline = try Self.makePipeline(device: device, library: library, name: "ndi_bgra_to_uyvy")
        rgbafToUyvyPipeline = try Self.makePipeline(device: device, library: library, name: "ndi_rgbaf_to_uyvy")
    }

    // MARK: - Decode

    /// Returns the compute pipeline for decoding an NDI wire buffer to a
    /// BGRA texture.
    ///
    /// - Parameter fourCC: The pixel format of the incoming NDI frame.
    /// - Returns: A compute pipeline state, or `nil` if the format is not
    ///   supported.
    ///
    /// Supported formats: `.bgra`, `.bgrx`, `.rgba`, `.rgbx`, `.uyvy`, `.p216`.
    public func decodePipeline(for fourCC: FourCC) -> MTLComputePipelineState? {
        if fourCC == .bgra || fourCC == .bgrx {
            return bgraPipeline
        }
        if fourCC == .rgba || fourCC == .rgbx {
            return rgbaPipeline
        }
        if fourCC == .uyvy {
            return uyvyPipeline
        }
        if fourCC == .p216 {
            return p216Pipeline
        }
        return nil
    }

    /// Computes the threads-per-grid for a decode dispatch.
    ///
    /// All decode kernels use 1 thread per pixel.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    /// - Returns: An `MTLSize` of `(width, height, 1)`.
    public func decodeThreadsPerGrid(width: Int, height: Int) -> MTLSize {
        MTLSize(width: width, height: height, depth: 1)
    }

    // MARK: - Encode

    /// Returns the compute pipeline for encoding a Metal texture to an NDI
    /// UYVY wire buffer.
    ///
    /// - Parameter source: The source texture format.
    /// - Returns: The matching compute pipeline state.
    public func encodePipeline(for source: NDIEncodeSource) -> MTLComputePipelineState {
        switch source {
        case .nv12:
            return nv12ToUyvyPipeline
        case .bgra:
            return bgraToUyvyPipeline
        case .rgbaFloat:
            return rgbafToUyvyPipeline
        }
    }

    /// Computes the threads-per-grid for an encode dispatch.
    ///
    /// All encode kernels process one 2-pixel UYVY macro-pixel per thread.
    ///
    /// - Parameters:
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    /// - Returns: An `MTLSize` of `((width + 1) / 2, height, 1)`.
    public func encodeThreadsPerGrid(width: Int, height: Int) -> MTLSize {
        MTLSize(width: (width + 1) / 2, height: height, depth: 1)
    }

    // MARK: - Threadgroup Sizing

    /// Computes a reasonable threads-per-threadgroup for the given pipeline.
    ///
    /// Uses the pipeline's `threadExecutionWidth` and
    /// `maxTotalThreadsPerThreadgroup` to fill a 2D threadgroup.
    ///
    /// - Parameter pipeline: The compute pipeline state to size for.
    /// - Returns: An `MTLSize` suitable for `dispatchThreads(_:threadsPerThreadgroup:)`.
    public func threadsPerThreadgroup(for pipeline: MTLComputePipelineState) -> MTLSize {
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        return MTLSize(width: w, height: h, depth: 1)
    }

    // MARK: - Private Helpers

    /// Loads the Metal library from the NDIKitMetal bundle resource.
    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: "NDIShaders", withExtension: "metallib")
                ?? bundle.url(forResource: "default", withExtension: "metallib") else {
            // Fall back to compiling from source if no precompiled metallib exists.
            // SPM processes .metal files in Resources/ into the bundle's default metallib.
            return try device.makeDefaultLibrary(bundle: bundle)
        }
        return try device.makeLibrary(URL: url)
    }

    /// Creates a compute pipeline state for the named function.
    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        name: String
    ) throws -> MTLComputePipelineState {
        guard let function = library.makeFunction(name: name) else {
            throw NDIVideoFormatConverterError.missingFunction(name)
        }
        return try device.makeComputePipelineState(function: function)
    }
}

// MARK: - Encode Source

/// The source format when encoding a Metal texture to an NDI UYVY wire buffer.
public enum NDIEncodeSource: Sendable {
    /// NV12 bi-planar textures from camera capture (r8Unorm luma + rg8Unorm chroma).
    case nv12
    /// 8-bit BGRA texture (`.bgra8Unorm`, sRGB / Rec.709).
    case bgra
    /// 16-bit float RGBA texture (`.rgba16Float`, Display P3).
    case rgbaFloat
}

// MARK: - Errors

/// Errors thrown during ``NDIVideoFormatConverter`` initialization.
public enum NDIVideoFormatConverterError: Error, Sendable {
    /// A required Metal shader function was not found in the library.
    case missingFunction(String)
}
