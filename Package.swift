// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskWidget",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TaskWidgetCore"),
        .executableTarget(name: "TaskWidget", dependencies: ["TaskWidgetCore"]),
        .testTarget(
            name: "TaskWidgetCoreTests",
            dependencies: ["TaskWidgetCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
