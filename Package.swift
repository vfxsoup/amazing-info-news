// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmazingNews",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AmazingNews", path: "Sources/AmazingNews")
    ]
)
