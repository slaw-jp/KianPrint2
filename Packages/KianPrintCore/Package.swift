// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KianPrintCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KianPrintCore", targets: ["KianPrintCore"])
    ],
    targets: [
        .target(name: "KianPrintCore"),
        .testTarget(name: "KianPrintCoreTests", dependencies: ["KianPrintCore"])
    ],
    swiftLanguageModes: [.v5]
)
