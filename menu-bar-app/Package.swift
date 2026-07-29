// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexTower",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CodexTower", targets: ["CodexTower"])],
    targets: [.executableTarget(name: "CodexTower")]
)
