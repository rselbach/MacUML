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
    targets: [
        .executableTarget(
            name: "MacUML",
            path: "Sources",
            exclude: ["Info.plist"],
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
