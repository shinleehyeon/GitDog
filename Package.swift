// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopGoose",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DesktopGoose", targets: ["DesktopGoose"]),
    ],
    targets: [
        .executableTarget(
            name: "DesktopGoose",
            path: "Sources/DesktopGoose"
        ),
    ]
)
