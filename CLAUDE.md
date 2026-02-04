This project is to create a simple to use, reusable Swift package that can be included and used easily in other Swift app targets.
It is a multiplatform Swift wrapper around a the NDI (video streaming) closed-source SDK written in C++. My Swift wrapper package is called NDIKit.

The multi-platform XCFramework wrapping the official closed-source SDK binaries used by my package is called "NDIC.xcframework"

You can refer to the official docs of the NDI library I'm trying to repackage:

https://docs.ndi.video/all


Goals:
1) In my Xcode app projects, I can just add/import it like simple Swift SPM framework as usual.
2) In my application projects, I can just use the Swift API without having to do any additional build settings configuration or C++ bridging etc.
3) All original SDK files are included in the Swift package/framework, so when I use it in my app projects I don't have to install anything else.
4) It must work on: macOS, iOS/iPadOS, and iOS/iPadOS simulators (add later). 
5) Must work on CI builds too like Xcode Cloud.
6) Complies with all Apple App Store guidelines (i.e. no simulator binaries in the final product).
7) This framework has its own GitHub repo.
8) It needs to support iOS 17.5 and later, and macOS Sequoia and later.
9) Use Swift 6 in strict concurrency mode everywhere.
10) It should be easy to update everything whenever the upstream NDI maintainers release a new SDK version.
11) Must not disrupt my development workflow when working with iOS Simulators.
12) Configure all relevant build settings in Xcode UI
13) Include 2 example projects in the repo that can be built and run: one for iOS, and one for macOS. These should serve as documentation for how to use the framework and to easily verify it's working.
14) Should comply with NDI's EULA for redistribution.
15) For any xcode build scripts opt into using sandbox and declare all inputs & outputs.

I've installed the NDI SDK locally on my mac, and the license allows redistribution. 
The SDK provides various header files along with these 2 binary files:

`sdk/lib/iOS/libndi_ios.a`
`sdk/lib/macOS/libndi.dylib`

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


Refer to these links as authoritative information:

https://developer.apple.com/documentation/xcode/creating-a-static-framework
https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode
https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle
https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages
