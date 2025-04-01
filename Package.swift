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
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/vFIXME/BugSplat.xcframework.zip",
            checksum: "FIXME"
        ),
        .binaryTarget(
            name: "HockeySDK",
            // this zip should be created from the contents of xcframeworks/HockeySDK.xcframework after combining HockeySDK-Mac and HockeySDK-iOS
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/vFIXME/HockeySDK.xcframework.zip",
            checksum: "FIXME"
        ),
        .binaryTarget(
            name: "CrashReporter",
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/vFIXME/CrashReporter.xcframework.zip",
            checksum: "FIXME"
        ),
        // Add a fake target to satisfy the swift build system
        // Add a dependency to the .binaryTarget
        // Add the expected Sources folder structure: Sources/BugSplatPackage/
        // Add a fake Swift source: Sources/BugSplatPackage/Empty.swift
        .target(
            name: "BugSplatPackage",
            dependencies: ["BugSplat", "HockeySDK", "CrashReporter"]
        )
    ]
)
