// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacUML",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacUML", targets: ["MacUML"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "MacUML",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources",
            exclude: ["Info.plist", "Entitlements.plist"],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/mermaid.min.js")
            ]
        ),
        .testTarget(
            name: "MacUMLTests",
            dependencies: ["MacUML"],
            path: "Tests"
        )
    ]
)
