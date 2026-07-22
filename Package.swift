// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ModelBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ModelBarCore", targets: ["ModelBarCore"]),
        .executable(name: "ModelBar", targets: ["ModelBar"]),
    ],
    targets: [
        .target(
            name: "ModelBarCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "ModelBar",
            dependencies: ["ModelBarCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "ModelBarCoreTests",
            dependencies: ["ModelBarCore"],
            resources: [
                .process("Fixtures"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
