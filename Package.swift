// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sandia",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Sandia", targets: ["Sandia"])
    ],
    targets: [
        .target(name: "SandiaCore"),
        .executableTarget(
            name: "Sandia",
            dependencies: ["SandiaCore"]
        ),
        .testTarget(
            name: "SandiaCoreTests",
            dependencies: ["SandiaCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
