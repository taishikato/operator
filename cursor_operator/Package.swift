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
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")
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
        .testTarget(
            name: "CursorOperatorCoreTests",
            dependencies: ["CursorOperatorCore"]
        )
    ]
)
