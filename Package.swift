// swift-tools-version:5.3
import PackageDescription

// Bundle up BugSplat.xcframework as a Swift Package suitable for integration with Swift Package Manager
let package = Package(
    name: "BugSplat",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_13)
    ],
    products: [
        .library(
            name: "BugSplat",
            targets: ["BugSplatPackage"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BugSplat",
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v1.2.6/BugSplat.xcframework.zip",
            checksum: "c88a6b05d83415b968e85745376fa997dc6ce19df865447ae6a21e2d7288400f"
        ),
        .binaryTarget(
            name: "CrashReporter",
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v1.2.6/CrashReporter.xcframework.zip",
            checksum: "d6e9f19c161fa6a29baa7792883409c3546df910cfbcc0f6dc55896ce4c5c588"
        ),
        // Add a fake target to satisfy the swift build system
        // Add a dependency to the .binaryTarget
        // Add the expected Sources folder structure: Sources/BugSplatPackage/
        // Add a fake Swift source: Sources/BugSplatPackage/Empty.swift
        .target(
            name: "BugSplatPackage",
            dependencies: ["BugSplat", "CrashReporter"],
            linkerSettings: [
                .linkedLibrary("z") // Required for zip compression
            ]
        )
    ]
)
