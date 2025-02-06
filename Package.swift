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
            targets: ["BugSplat"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BugSplat",
            url: "https://github.com/BugSplat-Git/bugsplat-apple/releases/download/v1.0.0/BugSplat.xcframework.zip",
            checksum: "2591da6aac9cd017a71d4881648eb130d1338c43deba7b8b6019c4cdf465ec25"
        ),
        // Add a fake target to satisfy the swift build system
        // Add a dependency to the .binaryTarget
        // Add the expected Sources folder structure: Sources/BugSplatPackage/
        // Add a fake Swift source: Sources/BugSplatPackage/Empty.swift
        .target(
            name: "BugSplatPackage",
            dependencies: ["BugSplat"]
        )
    ]
)