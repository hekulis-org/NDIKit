# AGENTS.md

## Project Summary
NDIKit is a Swift 6, strict-concurrency, multi-platform Swift Package that wraps the official NDI SDK. It ships the SDK assets as an XCFramework and provides a Swift-first API that can be embedded in app targets with minimal extra configuration.

This project is to create a simple to use, reusable Swift package that can be included and used easily in other Swift app targets.
It is a multiplatform Swift wrapper around a the NDI (video streaming) closed-source SDK written in C++. My Swift wrapper package is called NDIKit.

The multi-platform XCFramework wrapping the official closed-source SDK binaries used by my package is called "NDIC.xcframework"


## Project Goals and Constraints

1. In my Xcode app projects, I can just add/import it like simple Swift SPM framework as usual.
1. In my application projects, I can just use the Swift API without having to do any additional build settings configuration or C++ bridging etc.
1. All original SDK files are included in the Swift package/framework, so when I use it in my app projects I don't have to install anything else.
1. It must work on: macOS, iOS/iPadOS, and iOS/iPadOS simulators (add later). 
1. Must work on CI builds too like Xcode Cloud.
1. Complies with all Apple App Store guidelines (i.e. no simulator binaries in the final product).
1. This framework has its own GitHub repo.
1. It needs to support iOS 17.5 and later, and macOS Sequoia and later.
1. Use Swift 6 in strict concurrency mode everywhere.
1. It should be easy to update everything whenever the upstream NDI maintainers release a new SDK version.
1. Must not disrupt my development workflow when working with iOS Simulators.
1. Configure all relevant build settings in Xcode UI
1. Include 2 example projects in the repo that can be built and run: one for iOS, and one for macOS. These should serve as documentation for how to use the framework and to easily verify it's working.
1. Should comply with NDI's EULA for redistribution.
1. For any xcode build scripts opt into using sandbox and declare all inputs & outputs.
1. Use all modern Apple SDKs. i.e. Only use SwiftUI unless absolutely necessary to use UIKit.

## Upstream NDI SDK Info

When installing the NDI SDK locally on a mac, it provides various header files along with these 2 binary files:

`sdk/lib/iOS/libndi_ios.a`
`sdk/lib/macOS/libndi.dylib`


It seems like there are some challenges around how to get this working for both Mac and iOS, since the iOS library is static and the macOS library is dynamic. This is why we repackage it and combine all the SDK assets into an "NDIKit.xcframework" bundle.

Below are more details about the provided files:

```
$ lipo "lib/iOS/libndi_ios.a" -info
Architectures in the fat file: lib/iOS/libndi_ios.a are: x86_64 arm64

$ file "lib/iOS/libndi_ios.a"
lib/iOS/libndi_ios.a: Mach-O universal binary with 2 architectures: [x86_64:current ar archive] [arm64]
lib/iOS/libndi_ios.a (for architecture x86_64):	current ar archive
lib/iOS/libndi_ios.a (for architecture arm64):	current ar archive

$ lipo "lib/macOS/libndi.dylib" -info
Architectures in the fat file: lib/macOS/libndi.dylib are: x86_64 arm64

$ file "lib/macOS/libndi.dylib"
lib/macOS/libndi.dylib: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit dynamically linked shared library x86_64] [arm64]
lib/macOS/libndi.dylib (for architecture x86_64):	Mach-O 64-bit dynamically linked shared library x86_64
lib/macOS/libndi.dylib (for architecture arm64):	Mach-O 64-bit dynamically linked shared library arm64
```


It seems like there are some challenges around how to get this working for both Mac and iOS, since the iOS library is static and the macOS library is dynamic. From my research it seems the best path forward is to combine all the SDK assets into an "NDIKit.xcframework" bundle (definitely do NOT use a FatFramework approach as this is outdated). 

## Source of Truth
- High-level project goals and constraints: `CLAUDE.md`
- Build + SDK import steps: `README.md`
- Swift wrapper code: `NDIKit/Sources/NDIKit`
- Example apps:
  - macOS receiver: `Examples/NDIReceiverExample`
  - iOS sender: `Examples/NDISenderExample`

## Key Constraints & Decisions
- **Swift 6 strict concurrency** everywhere.
- **Metal 4 required** for rendering and GPU conversion paths.
- **iOS 26+** and **macOS Sequoia+** are the supported targets for the examples.
- **SwiftUI** should be used for all UI Code. Only use **UIKit**/**AppKit** when absolutely necessary.
- iOS **NDI discovery requires Bonjour**: `NSBonjourServices = _ndi._tcp` and Local Network permission.
- NDI SDK assets live in `Vendor/NDI-SDK` and are bundled into an XCFramework via `Scripts/build-xcframework.sh`.
- Example projects must build and run and serve as documentation.

## Concurrency & Threading
- Prefer Swift Concurrency (`Task`, `@MainActor`, actors) over GCD.
- **Avoid `DispatchQueue.main.async`**; use `Task { @MainActor in ... }` instead.
- AVFoundation **requires** a non-nil `DispatchQueue` for `AVCaptureVideoDataOutput.setSampleBufferDelegate(_:queue:)`. This is the only approved GCD usage.
- Avoid main-thread work for `AVCaptureSession.startRunning()`/`stopRunning()`; use `Task.detached` for those calls.

## Rendering & GPU Rules
- Do not render via SwiftUI `Image` for video. Use Metal/MetalKit.
- Perform format conversions on the GPU (compute shader), not CPU.
- Vertex shaders should use the simplified 4-vertex quad and `triangleStrip`.

## Code Style
- **Comment all classes, structs, enums, and their methods**.
- Keep comments concise and purpose-driven.

## iOS Sender Example Notes
- Uses camera capture, NV12 -> BGRA conversion on GPU, Metal preview, and NDI sender.
- Orientation handling uses `effectiveGeometry.interfaceOrientation` and `videoRotationAngle` (iOS 26+).
- `SUPPORTED_PLATFORMS = iphoneos` because the NDI C SDK lacks a simulator slice.

## macOS Receiver Example Notes
- Metal renderer consumes NDI frames via `NDIFrameConsumer`.
- Rendering is fully GPU-based; conversion pipelines cover multiple FourCC formats.

## Build & Distribution
- To rebuild the XCFramework:
  - Update `Vendor/NDI-SDK` with SDK libs/headers.
  - Run `./Scripts/build-xcframework.sh`.
  - Validate with `swift build` and `swift test`.

## Platform & Deployment
- Comply with App Store guidelines (no simulator binaries in final product).
- Maintain App Store-safe distribution of the NDI SDK (per EULA).


## Authoritative References

- https://docs.ndi.video/all
- https://developer.apple.com/documentation/xcode/creating-a-static-framework
- https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode
- https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
- https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle
- https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages
