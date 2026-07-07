// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FlashForgeUI",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FlashForgeNativeKit",
            targets: ["FlashForgeNativeKit"]
        ),
        .executable(
            name: "FlashForgeUI",
            targets: ["FlashForgeUI"]
        ),
        .executable(
            name: "FlashForgeMobile",
            targets: ["FlashForgeMobile"]
        )
    ],
    targets: [
        .target(
            name: "FlashForgeNativeKit"
        ),
        .executableTarget(
            name: "FlashForgeUI",
            dependencies: ["FlashForgeNativeKit"]
        ),
        .executableTarget(
            name: "FlashForgeMobile",
            dependencies: ["FlashForgeNativeKit"]
        ),
        .testTarget(
            name: "FlashForgeNativeKitTests",
            dependencies: ["FlashForgeNativeKit"]
        )
    ]
)
