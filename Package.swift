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
            // just for testing: forked from Kumulos/KSCrash which has the Package.swift added from kstenerud/KSCrash so we can import our fork in here with SPM support
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
