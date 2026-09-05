// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Crick",
    products: [
        .library(name: "CreekCore", targets: ["CreekCore"]),
        .executable(name: "crick", targets: ["CrickCLI"]),
    ],
    targets: [
        .target(name: "CreekCore"),
        .executableTarget(
            name: "CrickCLI",
            dependencies: ["CreekCore"]
        ),
        .testTarget(
            name: "CreekCoreTests",
            dependencies: ["CreekCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
