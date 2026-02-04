# NDIKit

This is a multi-platform Swift Package wrapper around the official NDI SDK.

It uses Swift 6 with strict concurrency.

Currently supported platforms: iOS, macOS.

**How it's Structured**

- The original SDK files are copied to: `/Vendor/NDI-SDK`.
- The build script patches and packages those into an XCFramework bundle for multi-platform use.
- Code in `NDIKit/Sources/NDIKit` is where all the Swift wrapper code lives.
- See 2 example projects for usage.

## Dev: Rebuilding this package

Copy the official SDK library files:
`cp -R /Library/NDI\ SDK\ for\ Apple/lib/{iOS,macOS} Vendor/NDI-SDK/lib/`

Copy the headers:
`cp -R /Library/NDI\ SDK\ for\ Apple/include/* Vendor/NDI-SDK/include/`

Run the build script:
`./Scripts/build-xcframework.sh`

Make sure it worked:
`swift build`
`swift test`

## TODO
- min os versions should be variables in the build script
- change development team in example apps

- simulator support
- script to refresh sdk files and rebuild framework
- hello world
- fill out wrapper stuff.
