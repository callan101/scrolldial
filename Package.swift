// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SmoothDial",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SmoothDial", targets: ["SmoothDial"]),
    ],
    targets: [
        .executableTarget(
            name: "SmoothDial",
            exclude: ["Info.plist", "Resources"]
        ),
    ]
)
