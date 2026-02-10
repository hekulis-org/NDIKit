# NDIKit

This is a multi-platform Swift Package wrapper around the official NDI SDK.

It uses Swift 6 with strict concurrency. It is packaged for Swift Package Manager.

The goal is that you can just import this package and get going without having to fiddle with low level C/C++ build configurations or have to use C++ code/API Objects inside of your Swift code.

Supported platforms: iOS, macOS.
NOTE: iOS Simulators are NOT supported b/c NDI does not provide SDK binaries for that platform.

## Usage

Add the Swift package as usual.
Refer to the example projects for detailed usage.

### Required Entitlements

Certain entitlements are required and must be configured by apps using this library.

- **NDI discovery requires Bonjour**: `NSBonjourServices = _ndi._tcp`
- **Local Network**
- **Multicast Networking**


### Networks Settings

Refer to [NDI's network switch settings](https://docs.ndi.video/all/using-ndi/using-ndi-with-hardware/recommended-network-switch-settings-for-ndi).

If multicast discovery is not working, you can configure receivers with IP address of senders.
Alternatively you can install the NDI Tools and run NDI Access Manager and provide sender IPs there.

### License

Note the [licensing requirements from the upstream NDI SDK](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing) that must be adhered to.

## Terminology Notes

NDI's SDK and Apple's CoreVideo APIs use different terms for video formats.

NDI’s docs emphasize UYVY/UYVA as the most compatible/perf-friendly send path.

NDI <==> Apple
`UYVY` (8-bit 4:2:2 packed) <==> kCVPixelFormatType_422YpCbCr8
`UYVA` (8-bit 4:2:2 + alpha) <==> No Apple equivalent
`NV12` <==> `420v`(limited range) or `420f`(full range).


---


# Developer Notes

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


## Not Implemented

NDI C SDK features not yet exposed in the NDIKit Swift wrapper:

**Sending**
- **Audio sending** (`NDIlib_send_send_audio_v2` / `v3`) — Send audio frames (planar float or via FourCC). The sender currently only supports video.
- **Metadata frame sending** (`NDIlib_send_send_metadata`) — Send standalone metadata frames, separate from per-frame video metadata.
- **Tally feedback** (`NDIlib_send_get_tally`) — Query whether connected receivers have this source on program or preview. Useful for on-air indicators.
- **Source name query** (`NDIlib_send_get_source_name`) — Get the resolved source name (including machine name) after creation.
- **Receive metadata from receivers** (`NDIlib_send_capture`) — Bidirectional metadata channel; receivers can send metadata back to the sender (e.g. PTZ commands).
- **Connection metadata** (`NDIlib_send_add_connection_metadata` / `clear`) — Metadata automatically sent to each new receiver on connect (e.g. capability announcements).
- **Failover source** (`NDIlib_send_set_failover`) — Designate a backup source that receivers should switch to if this sender goes offline.

**Audio Utilities**
- **Interleaved audio send helpers** (`NDIlib_util_send_send_audio_interleaved_16s/32s/32f`) — Convenience functions that accept interleaved 16-bit int, 32-bit int, or 32-bit float audio. The SDK handles conversion to planar internally.
- **Audio format conversions** (`NDIlib_util_audio_to/from_interleaved_*`) — Convert between planar and interleaved audio layouts without sending.

**Video Utilities**
- **V210 ↔ P216 conversion** (`NDIlib_util_V210_to_P216` / `P216_to_V210`) — Convert between 10-bit packed and 16-bit semi-planar video formats.


## TODO
- min os versions should be variables in the build script
- change development team in example apps
- include proper license files
- add tests
- comment all classes & methods
- sometimes see xcode warning: warning: umbrella header for module 'NDIKitC' does not include header 'Processing.NDI.Lib.cplusplus.h'
- maybe move some common useful metal conversion code over to the NDIKit pkg.

