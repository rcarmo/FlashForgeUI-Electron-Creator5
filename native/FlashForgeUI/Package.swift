// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FlashForgeNative",
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
            name: "FlashForgeNative",
            targets: ["FlashForgeNative"]
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
            name: "FlashForgeNative",
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
