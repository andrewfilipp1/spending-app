// swift-tools-version:5.9
import PackageDescription

// Platform-independent logic shared by the iOS app (and testable on the Mac with `swift test`).
let package = Package(
    name: "SpendingCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SpendingCore", targets: ["SpendingCore"])],
    targets: [
        .target(name: "SpendingCore"),
        .testTarget(name: "SpendingCoreTests", dependencies: ["SpendingCore"]),
    ]
)
