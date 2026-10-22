// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "soundable_proudp",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "soundable-proudp", targets: ["soundable_proudp"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // SoundableProudpLib main branch (includes call interrupt handling, not tagged yet)
        .package(
            url: "https://github.com/SoundableHealth/SoundableProudpLib.git",
            revision: "12e9b71ce1f55819869b2602a83602383339f694"
        ),
    ],
    targets: [
        .target(
            name: "soundable_proudp",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "SoundableProudpLib", package: "SoundableProudpLib"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
