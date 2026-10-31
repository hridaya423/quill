// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Quill",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "QuillCore"),
        .executableTarget(name: "Quill", dependencies: ["QuillCore"]),
        .testTarget(name: "QuillCoreTests", dependencies: ["QuillCore"]),
    ]
)
