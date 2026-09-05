// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EmbeddedSwiftUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EmbeddedSwiftUI", targets: ["EmbeddedSwiftUI"]),
        .library(name: "LVGLRendererAdaptor", targets: ["LVGLRendererAdaptor"]),
    ],
    targets: [
        .target(
            name: "EmbeddedSwiftUI",
            swiftSettings: [.enableExperimentalFeature("Embedded")]
        ),
        .target(
            name: "LVGLRendererAdaptor",
            dependencies: ["EmbeddedSwiftUI"],
            swiftSettings: [.enableExperimentalFeature("Embedded")]
        ),
    ]
)
