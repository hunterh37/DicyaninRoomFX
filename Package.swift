// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DicyaninRoomFX",
    platforms: [
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "DicyaninRoomFX",
            targets: ["DicyaninRoomFX"]
        )
    ],
    dependencies: [
        // Scene reconstruction mesh tracking + raycasts. RoomFX drives all of its
        // effects off the real scanned room geometry that this package exposes.
        .package(path: "../DicyaninSceneReconstruction")
    ],
    targets: [
        .target(
            name: "DicyaninRoomFX",
            dependencies: ["DicyaninSceneReconstruction"]
        ),
        .testTarget(
            name: "DicyaninRoomFXTests",
            dependencies: ["DicyaninRoomFX"]
        )
    ]
)
