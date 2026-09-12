// swift-tools-version:5.9
import PackageDescription

// A command-line macOS app on the BugSplat package from this repository (path dependency, so it
// builds against the working tree; real apps use the GitHub URL).
let package = Package(
    name: "HelloCrash",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "HelloCrash",
            dependencies: [.product(name: "BugSplat", package: "bugsplat-apple")]
        ),
    ]
)
