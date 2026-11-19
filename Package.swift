// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pluck",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .executable(name: "Pluck", targets: ["Pluck"]),
        .library(name: "PluckKit", targets: ["PluckKit"]),
        // The app shared by the Mac executable and the iPad project in ios/.
        .library(name: "PluckUI", targets: ["PluckUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0"),
        .package(url: "https://github.com/scooper4711/tabletop-kit.git", from: "1.11.4")
    ],
    targets: [
        .target(
            name: "PluckKit",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode"),
                .product(name: "TablesideShared", package: "tabletop-kit")
            ]
        ),
        .target(
            name: "PluckUI",
            dependencies: [
                "PluckKit", .product(name: "AppNotices", package: "tabletop-kit"),
                .product(name: "TablesideShared", package: "tabletop-kit")
            ]
        ),
        .executableTarget(name: "Pluck", dependencies: ["PluckUI"]),
        .testTarget(
            name: "PluckKitTests",
            dependencies: [
                "PluckKit", .product(name: "libwebp", package: "libwebp-Xcode"),
                .product(name: "TablesideShared", package: "tabletop-kit")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
