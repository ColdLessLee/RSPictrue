// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RSPicture",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "RSPictureCore",
            targets: ["RSPictureCore"]),
        .library(
            name: "AssetsService",
            targets: ["AssetsService"]),
        .library(
            name: "RSP",
            targets: ["RSP"]),
    ],
    dependencies: [
        // No external dependencies to keep the package lightweight
    ],
    targets: [
        .target(
            name: "RSPictureCore",
            dependencies: [],
            resources: [
                .process("Metal")
            ]
        ),
        .target(
            name: "AssetsService",
            dependencies: ["RSPictureCore"]
        ),
        .target(
            name: "RSP",
            dependencies: ["RSPictureCore", "AssetsService"]
        ),
        .testTarget(
            name: "RSPictureCoreTests",
            dependencies: ["RSPictureCore"])
    ]
) 