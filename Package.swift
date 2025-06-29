// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RspictureCore",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "RspictureCore",
            targets: ["RspictureCore"]),
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
            name: "RspictureCore",
            dependencies: [],
            resources: [
                .process("Metal")
            ]
        ),
        .target(
            name: "AssetsService",
            dependencies: ["RspictureCore"]
        ),
        .target(
            name: "RSP",
            dependencies: ["RspictureCore", "AssetsService"]
        ),
        .testTarget(
            name: "RspictureCoreTests",
            dependencies: ["RspictureCore"])
    ]
) 