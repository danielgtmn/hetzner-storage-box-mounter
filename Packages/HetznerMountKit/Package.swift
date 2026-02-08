// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HetznerMountKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HetznerMountKit", targets: ["HetznerMountKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "HetznerMountKit",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
            ]
        ),
    ]
)
