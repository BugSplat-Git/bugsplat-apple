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
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v1.2.5/BugSplat.xcframework.zip",
            checksum: "f6fa738601a7af8b2f95ff2697fe6221f70d707a5d386ced02532be3f95c6580"
        ),
        .binaryTarget(
            name: "HockeySDK",
            // this zip should be created from the contents of xcframeworks/HockeySDK.xcframework after combining HockeySDK-Mac and HockeySDK-iOS
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v1.2.5/HockeySDK.xcframework.zip",
            checksum: "03366d0e4bbeff763bc169df7ece551cf68652b16172f04031155e7aebe319a5"
        ),
        .binaryTarget(
            name: "CrashReporter",
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v1.2.5/CrashReporter.xcframework.zip",
            checksum: "e71125b0a375edeb99480b3865a3f0a954df1e39ffee0ae5bb9b3760d1b3c978"
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
