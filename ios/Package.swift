// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SecureDataFetcherCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SecureDataFetcherCore", targets: ["SecureDataFetcherCore"])
    ],
    targets: [
        .target(name: "SecureDataFetcherCore"),
        .testTarget(
            name: "SecureDataFetcherCoreTests",
            dependencies: ["SecureDataFetcherCore"]
        )
    ]
)
