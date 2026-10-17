// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CommonKeys",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "WorldKey", targets: ["WorldKey"]),
        .executable(name: "worldkey", targets: ["WorldKeyCLI"]),
        .executable(name: "LangSmart", targets: ["LangSmart"]),
    ],
    targets: [
        .target(name: "WorldKey"),
        .executableTarget(name: "LangSmart", dependencies: ["WorldKey"]),
        .executableTarget(name: "WorldKeyCLI", dependencies: ["WorldKey"]),
        .testTarget(name: "WorldKeyTests", dependencies: ["WorldKey"]),
    ]
)
