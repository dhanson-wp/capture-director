// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CaptureDirector",
    platforms: [.macOS(.v26)],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "CaptureDirectorKit"),
        .executableTarget(
            name: "CaptureDirector",
            dependencies: ["CaptureDirectorKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.defaultIsolation(MainActor.self)],
            // `import AVKit` links only _AVKit_SwiftUI with Command Line Tools, and
            // VideoPlayer then crashes looking up AVPlayerView. Link AVKit itself.
            linkerSettings: [.linkedFramework("AVKit")]
        ),
        .testTarget(name: "CaptureDirectorKitTests", dependencies: ["CaptureDirectorKit"]),
    ]
)
