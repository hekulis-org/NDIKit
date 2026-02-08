# NDIKit

This is a multi-platform Swift Package wrapper around the official NDI SDK.

It uses Swift 6 with strict concurrency. It is packaged for Swift Package Manager.

The goal is that you can just import this package and get going without having to fiddle with low level C/C++ build configurations or have to use C++ code/API Objects inside of your Swift code.

Supported platforms: iOS, macOS.
NOTE: iOS Simulators are NOT supported b/c NDI does not provide SDK binaries for that platform.

## Usage

Add the Swift package as usual.

Refer to the example projects for detailed usage.

**NDI discovery requires Bonjour**: `NSBonjourServices = _ndi._tcp` and Local Network permission entitlements must be added to your projects.

Refer to [NDI's network switch settings](https://docs.ndi.video/all/using-ndi/using-ndi-with-hardware/recommended-network-switch-settings-for-ndi).

Note the [licensing requirements from the upstream NDI SDK](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing) that must be adhered to.

## Terminology Notes

NDI's SDK and Apple's CoreVideo APIs use different terms for video formats.

NDI’s docs emphasize UYVY/UYVA as the most compatible/perf-friendly send path.

NDI <==> Apple
`UYVY` (8-bit 4:2:2 packed) <==> kCVPixelFormatType_422YpCbCr8
`UYVA` (8-bit 4:2:2 + alpha) <==> No Apple equivalent
`NV12` <==> `420v`(limited range) or `420f`(full range).


### Local Network Settings
Path: Settings → WiFi → <your SSID> → Advanced
Toggle Multicast Enhancement (IGMPv3) ON.
This converts multicast discovery traffic to unicast for Wi‑Fi clients and often fixes Bonjour/mDNS discovery


## Rebuilding the XCFramework

**How it's Structured**

- The original SDK files are copied to: `/Vendor/NDI-SDK`.
- The build script removes unnecessary architectures and packages the libraries and headers into an XCFramework bundle for multi-platform use.
- Code in `NDIKit/Sources/NDIKit` is where all the Swift wrapper code lives.
- See 2 example projects for usage.

**To Update to the latest SDK Version**

1. Install the latest NDI SDK on your mac.
1. Copy the official SDK library files:
`cp -R /Library/NDI\ SDK\ for\ Apple/lib/{iOS,macOS} Vendor/NDI-SDK/lib/`
1. Copy the headers:
`cp -R /Library/NDI\ SDK\ for\ Apple/include/* Vendor/NDI-SDK/include/`
1. Run the build script:
`./Scripts/build-xcframework.sh`
1. Make sure it worked:
`swift build`
`swift test`


## TODO
- min os versions should be variables in the build script
- change development team in example apps
- include proper license files
- add tests
- comment all classes & methods
- add DocC comments to everything public in the NDIKit wrapper code.
- any way around using @unchecked Sendable?
- sometimes see xcode warning: warning: umbrella header for module 'NDIKitC' does not include header 'Processing.NDI.Lib.cplusplus.h'
- maybe move some common useful metal conversion code over to the NDIKit pkg.

