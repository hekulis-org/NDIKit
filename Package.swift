// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NDIKit",
    platforms: [
        // Supported platforms.
        .macOS(.v15),  // macOS Sequoia
        .iOS(.v17),    // iOS 17.5+ (17.0 is the minimum for .v17)
    ],
    products: [
        // Main library for users to import.
        .library(
            name: "NDIKit",
            targets: ["NDIKit"]
        ),
        // Metal compute shaders for NDI format conversion.
        .library(
            name: "NDIKitMetal",
            targets: ["NDIKitMetal"]
        ),
    ],


    targets: [
        
        // Swift wrapper - this is what users interact with
        .target(
            name: "NDIKit",
            dependencies: ["NDIKitC"],
            path: "NDIKit/Sources/NDIKit",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                // NDI SDK dependencies - required for the static iOS library
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("VideoToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
            ]
        ),

        // Metal compute shaders for NDI format conversion.
        .target(
            name: "NDIKitMetal",
            dependencies: ["NDIKit"],
            path: "NDIKit/Sources/NDIKitMetal",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
            ]
        ),

        // Binary XCFramework containing the NDI SDK.
        // Hosted on GitHub Releases. Updated by Scripts/release.sh.
        // Binary URL must use the GitHub API asset format (not browser download URL).
        // Xcode's SPM resolver cannot follow the 302 redirect from browser URLs.
        // The asset ID is set automatically by Scripts/release.sh after upload.
        .binaryTarget(
            name: "NDIKitC",
            url: "https://api.github.com/repos/hekulis-org/NDIKit/releases/assets/354177307.zip",
            checksum: "e17550d80f2dc2c8b83e5b1d9867c52b87080fce97f1b1eb19308367fe766764"
        ),


        .testTarget(
            name: "NDIKitTests",
            dependencies: ["NDIKit"],
            path: "NDIKit/Tests/NDIKitTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),

    ],

    swiftLanguageModes: [.v6]

)
