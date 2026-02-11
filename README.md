# NDIKit

NDIKit is a multi-platform Swift wrapper around the official NDI SDK C libraries.

It uses Swift 6 with strict concurrency. It is packaged for use with Swift Package Manager.

The goal is that you can just import this package and get going without having to fiddle with low level C/C++ build configurations or have to use C++ code/API Objects inside of your Swift code.

Supported platforms: iOS, macOS.
NOTE: iOS Simulators are NOT supported because NDI does not provide SDK binaries for the simulator architecture. See [iOS Simulator Development](#ios-simulator-development) for a recommended workaround.

## Usage

- Add the Swift package as usual.
- Add the required entitlements to your project.
- Refer to the example projects for detailed usage.

### iOS Simulator Development

The NDI SDK does not ship simulator binaries, so SPM cannot resolve the NDIKitC binary target when building for iOS Simulator. This means any target that depends on NDIKit will fail to build for the simulator.

The recommended workaround is to create a **separate Xcode target** in your app project that excludes the NDIKit dependency, and use that target for simulator-based development:

1. **Duplicate your app target.** In Xcode, right-click your app target → *Duplicate*. Rename it to something like `MyApp (Simulator)`.

2. **Remove NDIKit from the simulator target.** Select the new target → *General* → *Frameworks, Libraries, and Embedded Content* → remove NDIKit.

3. **Add a compiler flag.** In the simulator target's build settings, add `-DSIMULATOR_BUILD` to *Other Swift Flags* (`OTHER_SWIFT_FLAGS`). This lets you conditionally compile out NDI-dependent code.

4. **Guard NDI code with conditional compilation.** Wrap any code that imports or uses NDIKit:

   ```swift
   #if !SIMULATOR_BUILD
   import NDIKit

   func startNDI() {
       NDI.initialize()
       // ...
   }
   #else
   func startNDI() {
       print("NDI not available in simulator builds")
   }
   #endif
   ```

5. **Use the simulator target for day-to-day development.** Switch to the real target when building for a physical device or for distribution.

This keeps NDIKit's source code clean and puts the simulator workaround where it belongs — in your app project.

### Required Entitlements

Certain entitlements are required and must be configured by apps using this library.

- **NDI discovery requires Bonjour for Multicast discovery**: `NSBonjourServices = _ndi._tcp`
- **Local Network access**
- **App Sandbox: Incoming Connections, Outgoing Connections** (macOS only)


### Networks Settings

Refer to [NDI's network switch settings](https://docs.ndi.video/all/using-ndi/using-ndi-with-hardware/recommended-network-switch-settings-for-ndi).

If multicast discovery is not working, you can configure receivers with IP address of senders.
Alternatively you can install the NDI Tools and run NDI Access Manager and provide sender IPs there.


## Terminology Notes

NDI's SDK and Apple's CoreVideo APIs use different terms for video formats.

NDI’s docs emphasize UYVY/UYVA as the most compatible/perf-friendly send path.

NDI <==> Apple  
`UYVY` (8-bit 4:2:2 packed) <==> kCVPixelFormatType_422YpCbCr8  
`UYVA` (8-bit 4:2:2 + alpha) <==> No Apple equivalent  
`NV12` <==> `420v`(limited range) or `420f`(full range)  


---


# Developer Notes

How to update/contribute to this package.

## Building the XCFramework

**How it's Structured**

- The original SDK files are copied to: `/Vendor/NDI-SDK` from the SDK default installation directory.
- The build script removes unnecessary architectures, then packages the libraries and headers into an XCFramework bundle for multi-platform use.
- Code in `NDIKit/Sources/NDIKit` is where all the Swift wrapper code lives.
- Code in `NDIKit/Sources/NDIKitMetal` is another package with some convenient Metal code to convert video formats etc.
- See 2 example projects for usage.

**To Update to the latest SDK Version**

1. Install the latest NDI SDK on your mac.
1. Copy the official SDK library files:
`cp -R /Library/NDI\ SDK\ for\ Apple/lib/{iOS,macOS} Vendor/NDI-SDK/lib/`
1. Copy the headers:
`cp -R /Library/NDI\ SDK\ for\ Apple/include/* Vendor/NDI-SDK/include/`
1. Run the build script with the version matching the NDI SDK:
`./Scripts/build-xcframework.sh <version>`
1. Publish to GitHub Releases:
`./Scripts/release.sh <version>`

## Binary Distribution

The NDIKitC.xcframework binary is hosted as a zip on GitHub Releases and referenced as a remote `.binaryTarget` in Package.swift. This avoids Git LFS and keeps the repo small.

The `Frameworks/` directory is `.gitignore`d. It is only used locally during the build/release workflow.
The `Vendor/NDI-SDK/` directory is `.gitignore`d. It is only used locally during the build/release workflow.

**Important:** Package.swift must use the GitHub **API asset URL** format (`https://api.github.com/repos/.../releases/assets/ID.zip`), not the browser download URL. Xcode's SPM resolver cannot follow the 302 redirect from browser URLs. The `release.sh` script handles this automatically.

**Release workflow:**

1. `./Scripts/build-xcframework.sh <version>` — Builds the XCFramework, creates a zip, and computes the SHA-256 checksum. The version is embedded in the framework's `CFBundleShortVersionString`.
2. `./Scripts/release.sh <version>` — Creates a draft GitHub Release, uploads the zip, looks up the asset ID, updates `Package.swift` with the API URL + checksum, commits, tags, pushes, then publishes the release.

To delete a release: `./Scripts/delete-release.sh <version>`


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


---


# License

- Repository licensing scope is documented in `LICENSE`.
- NDIKit-authored code in this repository is licensed under MIT: see `NDIKit/LICENSE`.
- Third-party NDI SDK licensing, attribution, and pass-through requirements are documented in `THIRD_PARTY_NOTICES.md`.
- NDI SDK files are not relicensed by NDIKit and remain under upstream NDI terms.
