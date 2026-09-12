// swift-tools-version:5.9
import PackageDescription

// BugSplat for Apple platforms, 9.0: a Swift API over bugsplat-native's C ABI.
//
// Two targets:
//   BugSplatNative  the binary framework produced by bugsplat-native
//                   (libbugsplat + BugSplatMonitor + BugSplatReporter.app on macOS).
//                   During development and in CI it is built into Frameworks/ by
//                   scripts/build-native.sh; releases replace `path:` with a
//                   `url:`/`checksum:` pair pointing at the GitHub release asset.
//   BugSplat        the Swift API (this repository).
let package = Package(
    name: "BugSplat",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
        .tvOS(.v15),
    ],
    products: [
        .library(name: "BugSplat", targets: ["BugSplat"]),
    ],
    targets: [
        .binaryTarget(
            name: "BugSplatNative",
            path: "Frameworks/BugSplatNative.xcframework"
        ),
        .target(
            name: "BugSplat",
            dependencies: ["BugSplatNative"],
            path: "Sources/BugSplat",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("IOKit", .when(platforms: [.macOS])),
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS])),
                .linkedLibrary("c++"),
                .linkedLibrary("z"),
                .linkedLibrary("bsm", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "BugSplatTests",
            dependencies: ["BugSplat"],
            path: "Tests/BugSplatTests"
        ),
    ]
)
