// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Steward",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Steward", targets: ["Steward"])
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.1.3")
    ],
    targets: [
        .executableTarget(
            name: "Steward",
            dependencies: ["HotKey"]
        )
    ]
)
