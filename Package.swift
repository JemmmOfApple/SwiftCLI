// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CLITool",
    platforms: [.macOS(.v10_15)],
    products: [
        .executable(name: "swiftcli", targets: ["SwiftCLI"]) // <-- command name
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-syntax.git", exact: "600.0.1")
    ],
    targets: [
        .executableTarget(
            name: "SwiftCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
    ]
)
