// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ScrollMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ScrollMonitor", targets: ["ScrollMonitor"]),
        .executable(name: "StripScrollLines", targets: ["StripScrollLines"]),
        .executable(name: "SmoothDial", targets: ["SmoothDial"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephancasas/CGEventSupervisor", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ScrollMonitor",
            dependencies: [
                .product(name: "CGEventSupervisor", package: "CGEventSupervisor"),
            ]
        ),
        .executableTarget(
            name: "StripScrollLines"
        ),
        .executableTarget(
            name: "SmoothDial",
            exclude: ["Info.plist"]
        ),
    ]
)
