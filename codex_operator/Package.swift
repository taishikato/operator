// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OperatorDesktop",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "OperatorDesktop",
            targets: ["OperatorDesktop"]
        ),
        .executable(
            name: "Operator",
            targets: ["OperatorApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")
    ],
    targets: [
        .target(
            name: "OperatorDesktop",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "OperatorApp",
            dependencies: ["OperatorDesktop"]
        ),
        .testTarget(
            name: "OperatorDesktopTests",
            dependencies: ["OperatorDesktop"]
        )
    ]
)
