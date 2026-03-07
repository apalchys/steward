// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Steward",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "StewardCore", targets: ["StewardCore"]),
        .executable(name: "Steward", targets: ["Steward"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
        .package(url: "https://github.com/square/Valet", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "StewardCore",
            dependencies: []
        ),
        .executableTarget(
            name: "Steward",
            dependencies: [
                "HotKey",
                "StewardCore",
                "Defaults",
                "Valet",
            ]
        ),
        .testTarget(
            name: "StewardTests",
            dependencies: ["StewardCore", "Steward"]
        ),
    ]
)
