// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pluck",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Pluck", targets: ["Pluck"]),
        .library(name: "PluckKit", targets: ["PluckKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "PluckKit",
            dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")]
        ),
        .executableTarget(name: "Pluck", dependencies: ["PluckKit"]),
        .testTarget(
            name: "PluckKitTests",
            dependencies: ["PluckKit", .product(name: "libwebp", package: "libwebp-Xcode")]
        )
    ],
    swiftLanguageModes: [.v5]
)
