// swift-tools-version:5.3
import PackageDescription

// Bundle up BugSplat.xcframework as a Swift Package suitable for integration with Swift Package Manager
// PLCrashReporter is statically linked into BugSplat - no separate framework needed
let package = Package(
    name: "BugSplat",
    platforms: [
        .iOS(.v13),
        .macOS("11.5"),
        .tvOS(.v13)
    ],
    products: [
        .library(
            name: "BugSplat",
            targets: ["BugSplatPackage"]
        )
    ],
    targets: [
        // For releases: update the URL and checksum to point to the GitHub release
        // BugSplat.xcframework contains PLCrashReporter statically linked
        .binaryTarget(
            name: "BugSplat",
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v2.0.0/BugSplat.xcframework.zip",
            checksum: "2bca1b543b7c4ca846c405febfbb4f82ffe00af7d8822d9461b7757cb2248236"
        ),
        // Wrapper target that links dependencies
        // Sources/BugSplatPackage/Empty.swift satisfies SPM's requirement for source files
        .target(
            name: "BugSplatPackage",
            dependencies: ["BugSplat"],
            linkerSettings: [
                .linkedLibrary("z"), // Required for zip compression
                .linkedLibrary("c++") // Required by PLCrashReporter (statically linked)
            ]
        )
    ]
)
