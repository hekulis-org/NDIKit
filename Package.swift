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
    ],


    targets: [
        
        // Swift wrapper - this is what users interact with
        .target(
            name: "NDIKit",
            dependencies: ["NDIKitC"],
            path: "Sources/NDIKit",
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

        // Binary XCFramework containing the NDI SDK
        .binaryTarget(
            name: "NDIKitC",
            path: "Frameworks/NDIKitC.xcframework"
        ),


        .testTarget(
            name: "NDIKitTests",
            dependencies: ["NDIKit"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),

    ],

    swiftLanguageModes: [.v6]

)
