// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Steward",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "StewardCore", targets: ["StewardCore"]),
        .executable(name: "Steward", targets: ["Steward"]),
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
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
            ]
        ),
        .testTarget(
            name: "StewardTests",
            dependencies: ["StewardCore", "Steward"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
