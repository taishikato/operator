// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OperatorDesktop",
    platforms: [
        .macOS(.v15)
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
    targets: [
        .target(
            name: "OperatorDesktop"
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
