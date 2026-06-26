// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CursorOperator",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "CursorOperatorCore",
            targets: ["CursorOperatorCore"]
        ),
        .executable(
            name: "CursorOperator",
            targets: ["CursorOperatorApp"]
        ),
        .executable(
            name: "CursorOperatorSmokeSupport",
            targets: ["CursorOperatorSmokeSupport"]
        ),
        .executable(
            name: "cursor-operator-cli",
            targets: ["CursorOperatorCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "CursorOperatorCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "CursorOperatorApp",
            dependencies: ["CursorOperatorCore"]
        ),
        .executableTarget(
            name: "CursorOperatorSmokeSupport",
            dependencies: ["CursorOperatorCore"]
        ),
        .target(
            name: "CursorOperatorCLICore",
            dependencies: ["CursorOperatorCore"]
        ),
        .executableTarget(
            name: "CursorOperatorCLI",
            dependencies: [
                "CursorOperatorCLICore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "CursorOperatorCoreTests",
            dependencies: [
                "CursorOperatorCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "CursorOperatorCLICoreTests",
            dependencies: ["CursorOperatorCLICore"]
        ),
        .testTarget(
            name: "CursorOperatorCLIIntegrationTests",
            dependencies: ["CursorOperatorCLI"]
        )
    ]
)
