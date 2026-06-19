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
        )
    ],
    targets: [
        .target(name: "CursorOperatorCore"),
        .executableTarget(
            name: "CursorOperatorApp",
            dependencies: ["CursorOperatorCore"]
        ),
        .testTarget(
            name: "CursorOperatorCoreTests",
            dependencies: ["CursorOperatorCore"]
        )
    ]
)
