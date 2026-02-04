//
//  VideoFrameConverter.swift
//  NDIReceiverExample
//
//  Created by Ed on 04.02.26.
//

import CoreGraphics
import Foundation
import NDIKit
import Accelerate

/// Converts NDI video frames to CGImage for display.
nonisolated enum VideoFrameConverter {

    /// Convert an NDI video frame to a CGImage.
    /// Supports BGRA/BGRX (8-bit) and P216 (16-bit YUV 4:2:2) formats.
    static func convert(_ frame: NDIVideoFrame) -> CGImage? {
        let fourCC = frame.fourCC

        if fourCC == .bgra || fourCC == .bgrx {
            return convertBGRA(frame)
        } else if fourCC == .rgba || fourCC == .rgbx {
            return convertRGBA(frame)
        } else if fourCC == .p216 {
            return convertP216(frame)
        } else if fourCC == .uyvy {
            return convertUYVY(frame)
        } else {
            print("VideoFrameConverter: Unsupported format \(fourCC) (raw: \(fourCC.rawValue))")
            return nil
        }
    }

    // MARK: - 8-bit BGRA/BGRX

    private static func convertBGRA(_ frame: NDIVideoFrame) -> CGImage? {
        guard let data = frame.copyData() else {
            print("VideoFrameConverter: Failed to copy frame data for BGRA")
            return nil
        }

        // Validate data size
        let expectedSize = frame.lineStride * frame.height
        guard data.count >= expectedSize else {
            print("VideoFrameConverter: Data size mismatch. Got \(data.count), expected \(expectedSize)")
            return nil
        }

        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.noneSkipFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let provider = CGDataProvider(data: data as CFData) else {
            print("VideoFrameConverter: Failed to create data provider for BGRA")
            return nil
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            print("VideoFrameConverter: Failed to create color space")
            return nil
        }

        let image = CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.lineStride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )

        if image == nil {
            print("VideoFrameConverter: CGImage creation failed for BGRA \(frame.width)x\(frame.height), stride=\(frame.lineStride)")
        }

        return image
    }

    // MARK: - 8-bit RGBA/RGBX

    private static func convertRGBA(_ frame: NDIVideoFrame) -> CGImage? {
        guard let data = frame.copyData() else { return nil }

        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.noneSkipLast.rawValue |
            CGBitmapInfo.byteOrderDefault.rawValue
        )

        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        return CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.lineStride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - UYVY (8-bit YUV 4:2:2)

    private static func convertUYVY(_ frame: NDIVideoFrame) -> CGImage? {
        guard let srcData = frame.data else { return nil }

        let width = frame.width
        let height = frame.height
        let srcStride = frame.lineStride

        // Output: BGRA (4 bytes per pixel)
        let dstBytesPerRow = width * 4
        var dstData = Data(count: dstBytesPerRow * height)

        dstData.withUnsafeMutableBytes { dstPtr in
            guard let dstBase = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }

            for y in 0..<height {
                let srcRow = srcData.baseAddress!.advanced(by: y * srcStride)
                let dstRow = dstBase.advanced(by: y * dstBytesPerRow)

                for x in stride(from: 0, to: width, by: 2) {
                    let uyvyOffset = x * 2
                    let u = Int(srcRow[uyvyOffset])
                    let y0 = Int(srcRow[uyvyOffset + 1])
                    let v = Int(srcRow[uyvyOffset + 2])
                    let y1 = Int(srcRow[uyvyOffset + 3])

                    // Convert YUV to RGB (BT.601)
                    let (r0, g0, b0) = yuvToRGB(y: y0, u: u, v: v)
                    let (r1, g1, b1) = yuvToRGB(y: y1, u: u, v: v)

                    // BGRA format
                    let dstOffset0 = x * 4
                    dstRow[dstOffset0] = b0
                    dstRow[dstOffset0 + 1] = g0
                    dstRow[dstOffset0 + 2] = r0
                    dstRow[dstOffset0 + 3] = 255

                    let dstOffset1 = (x + 1) * 4
                    dstRow[dstOffset1] = b1
                    dstRow[dstOffset1 + 1] = g1
                    dstRow[dstOffset1 + 2] = r1
                    dstRow[dstOffset1 + 3] = 255
                }
            }
        }

        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.noneSkipFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )

        guard let provider = CGDataProvider(data: dstData as CFData) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: dstBytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - P216 (16-bit YUV 4:2:2)

    private static func convertP216(_ frame: NDIVideoFrame) -> CGImage? {
        guard let srcData = frame.data else { return nil }

        let width = frame.width
        let height = frame.height
        let srcStride = frame.lineStride

        // P216 is planar: Y plane followed by interleaved UV plane
        // Y plane: width * height * 2 bytes (16-bit per pixel)
        // UV plane: width * height bytes (16-bit U and V interleaved, 4:2:2)
        let yPlaneSize = srcStride * height
        let srcBase = UnsafeRawPointer(srcData.baseAddress!)
        let yPlane = srcBase.assumingMemoryBound(to: UInt16.self)
        let uvPlane = srcBase.advanced(by: yPlaneSize).assumingMemoryBound(to: UInt16.self)

        // Output: 16-bit RGB (6 bytes per pixel)
        let dstBytesPerRow = width * 8  // 16-bit RGBA = 8 bytes per pixel
        var dstData = Data(count: dstBytesPerRow * height)

        // Y stride in UInt16 elements
        let yStrideElements = srcStride / 2

        dstData.withUnsafeMutableBytes { dstPtr in
            guard let dstBase = dstPtr.baseAddress?.assumingMemoryBound(to: UInt16.self) else { return }

            for row in 0..<height {
                let yRow = yPlane.advanced(by: row * yStrideElements)
                let uvRow = uvPlane.advanced(by: row * yStrideElements)
                let dstRow = dstBase.advanced(by: row * width * 4)  // 4 components per pixel

                for x in stride(from: 0, to: width, by: 2) {
                    // Get Y values (16-bit)
                    let y0 = Int(yRow[x])
                    let y1 = Int(yRow[x + 1])

                    // Get U and V values (interleaved, one pair per 2 pixels)
                    let uvIndex = x  // UV is interleaved as U, V, U, V...
                    let u = Int(uvRow[uvIndex])
                    let v = Int(uvRow[uvIndex + 1])

                    // Convert YUV to RGB (16-bit, BT.709)
                    let (r0, g0, b0) = yuvToRGB16(y: y0, u: u, v: v)
                    let (r1, g1, b1) = yuvToRGB16(y: y1, u: u, v: v)

                    // RGBA format (16-bit per component)
                    let dstOffset0 = x * 4
                    dstRow[dstOffset0] = r0
                    dstRow[dstOffset0 + 1] = g0
                    dstRow[dstOffset0 + 2] = b0
                    dstRow[dstOffset0 + 3] = 65535  // Alpha

                    let dstOffset1 = (x + 1) * 4
                    dstRow[dstOffset1] = r1
                    dstRow[dstOffset1 + 1] = g1
                    dstRow[dstOffset1 + 2] = b1
                    dstRow[dstOffset1 + 3] = 65535  // Alpha
                }
            }
        }

        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.noneSkipLast.rawValue |
            CGBitmapInfo.byteOrder16Big.rawValue
        )

        guard let provider = CGDataProvider(data: dstData as CFData) else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: dstBytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - YUV to RGB Conversion

    /// Convert 8-bit YUV to RGB using BT.601 coefficients.
    private static func yuvToRGB(y: Int, u: Int, v: Int) -> (UInt8, UInt8, UInt8) {
        let c = y - 16
        let d = u - 128
        let e = v - 128

        let r = clamp8((298 * c + 409 * e + 128) >> 8)
        let g = clamp8((298 * c - 100 * d - 208 * e + 128) >> 8)
        let b = clamp8((298 * c + 516 * d + 128) >> 8)

        return (r, g, b)
    }

    /// Convert 16-bit YUV to RGB using BT.709 coefficients.
    private static func yuvToRGB16(y: Int, u: Int, v: Int) -> (UInt16, UInt16, UInt16) {
        // Scale from 16-bit range to working range
        // Y: 16-235 scaled to 16-bit -> 4096-60160
        // U/V: 16-240 centered at 128 scaled to 16-bit -> centered at 32768
        let yScaled = y - 4096
        let uScaled = u - 32768
        let vScaled = v - 32768

        // BT.709 coefficients scaled for 16-bit
        // R = Y + 1.5748 * V
        // G = Y - 0.1873 * U - 0.4681 * V
        // B = Y + 1.8556 * U

        let yNorm = (yScaled * 65535) / 56064  // Normalize Y to full range
        let r = clamp16(yNorm + (vScaled * 103206) / 65536)
        let g = clamp16(yNorm - (uScaled * 12276) / 65536 - (vScaled * 30679) / 65536)
        let b = clamp16(yNorm + (uScaled * 121609) / 65536)

        return (r, g, b)
    }

    private static func clamp8(_ value: Int) -> UInt8 {
        UInt8(clamping: max(0, min(255, value)))
    }

    private static func clamp16(_ value: Int) -> UInt16 {
        UInt16(clamping: max(0, min(65535, value)))
    }
}
