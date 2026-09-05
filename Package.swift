// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Crick",
    products: [
        .library(name: "CreekCore", targets: ["CreekCore"]),
        .library(name: "CreekRunner", targets: ["CreekRunner"]),
        .executable(name: "crick", targets: ["CrickCLI"]),
    ],
    targets: [
        .target(name: "CreekCore"),
        .target(name: "CreekRunner", dependencies: ["CreekCore"]),
        .executableTarget(
            name: "CrickCLI",
            dependencies: ["CreekCore", "CreekRunner"]
        ),
        .testTarget(
            name: "CreekCoreTests",
            dependencies: ["CreekCore", "CreekRunner"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
