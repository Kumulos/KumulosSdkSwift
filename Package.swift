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
            url: "https://github.com/Kumulos/KSCrash.git", .exact("1.15.21-kumulos.4")
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
            path: "Sources/SDK",
            exclude: [
                "Info.plist"
            ]
        ),
        .target(
            name: "KumulosSDKExtension",
            dependencies: [
                "KumulosSDKObjC",
            ],
            path: "Sources/Extension",
            exclude: [
                "Info.plist"
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
