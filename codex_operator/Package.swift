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
        ),
        // Named operator-cli because an executable literally named "operator"
        // would collide with the Operator app product on macOS's
        // case-insensitive filesystem; install scripts symlink it as `operator`.
        .executable(
            name: "operator-cli",
            targets: ["OperatorCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
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
        .target(
            name: "OperatorCLICore",
            dependencies: ["OperatorDesktop"]
        ),
        .executableTarget(
            name: "OperatorCLI",
            dependencies: [
                "OperatorCLICore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "OperatorDesktopTests",
            dependencies: ["OperatorDesktop"]
        ),
        .testTarget(
            name: "OperatorCLICoreTests",
            dependencies: ["OperatorCLICore"]
        )
    ]
)
