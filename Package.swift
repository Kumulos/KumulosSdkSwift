// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "KumulosSDK",
    platforms: [
        .iOS(.v9)
    ],
    products: [
        .library(
            name: "KumulosSDK",
            targets: ["KumulosSDK"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/Kumulos/KSCrash",
            .branch("master")
        ),
    ],
    targets: [
        .target(
            name: "KumulosSDKObjC",
            dependencies: [],
            path: "KumulosSDKObjC",
            cSettings: [
                  .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "KumulosSDK",
            dependencies: [
                "KumulosSDKObjC",
                "KSCrash"
            ],
            path: "Sources",
            exclude: [
                "Extension"
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
