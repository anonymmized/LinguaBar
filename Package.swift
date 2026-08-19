// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LinguaBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LinguaBar", targets: ["LinguaBar"])
    ],
    targets: [
        .executableTarget(
            name: "LinguaBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
