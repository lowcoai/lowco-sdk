// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LowcoEngage",
    platforms: [
        .iOS(.v14),
        .macOS(.v12),
    ],
    products: [
        .library(name: "LowcoEngage", targets: ["LowcoEngage"]),
    ],
    targets: [
        .target(
            name: "LowcoEngage",
            path: "Sources/LowcoEngage",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "LowcoEngageTests",
            dependencies: ["LowcoEngage"],
            path: "Tests/LowcoEngageTests"
        ),
    ]
)
