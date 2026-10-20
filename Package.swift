// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "yue-hidpi",
    platforms: [.macOS(.v11)],
    products: [
        .executable(name: "yue-hidpi", targets: ["yue-hidpi"])
    ],
    targets: [
        .target(
            name: "YueHiDPICore",
            path: "Sources/YueHiDPICore"
        ),
        .executableTarget(
            name: "yue-hidpi",
            dependencies: ["YueHiDPICore"],
            path: "Sources/yue-hidpi"
        ),
        .testTarget(
            name: "YueHiDPICoreTests",
            dependencies: ["YueHiDPICore"],
            path: "Tests/YueHiDPICoreTests"
        )
    ]
)
