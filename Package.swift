// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "KumulosSDK",
    platforms: [
        .iOS(.v10)
    ],
    products: [
        .library(
            name: "KumulosSDK",
            targets: ["KumulosSDK"]),
        .library(
            name: "KumulosSDKExtension",
            targets: ["KumulosSDKExtension"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/Kumulos/KSCrash",
            .branch("master")
        )
    ],
    targets: [
        .target(
            name: "KumulosSDKObjC",
            dependencies: [],
            path: "Sources/ObjC",
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
            path: "Sources/SDK"
        ),
        .target(
            name: "KumulosSDKExtension",
            dependencies: [
                "KumulosSDKObjC",
                "KSCrash"
            ],
            path: "Sources/Extension"
        )
    ],
    swiftLanguageVersions: [.v5]
)
