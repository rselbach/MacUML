// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MacUML",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MacUML", targets: ["MacUML"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.6.4")
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
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/preview.html")
            ]
        ),
        .testTarget(
            name: "MacUMLTests",
            dependencies: ["MacUML"],
            path: "Tests"
        )
    ]
)
