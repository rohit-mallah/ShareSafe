// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShareSafe",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ShareSafe", targets: ["ShareSafe"])],
    targets: [
        .target(name: "ShareSafeCore"),
        .executableTarget(name: "ShareSafe", dependencies: ["ShareSafeCore"]),
        .testTarget(name: "ShareSafeCoreTests", dependencies: ["ShareSafeCore"]),
        .testTarget(name: "ShareSafeTests", dependencies: ["ShareSafe"])
    ]
)
