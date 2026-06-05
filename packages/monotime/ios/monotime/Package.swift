// swift-tools-version: 5.9
// !! DO NOT rename 'monotime' — Flutter's SPM bridge expects the product
// name to match the plugin's Dart package name exactly (lowercase, no hyphens).
import PackageDescription

let package = Package(
    name: "monotime",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_14),
    ],
    products: [
        // Product name MUST match the Flutter plugin name.
        .library(name: "monotime", targets: ["monotime"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "monotime",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/monotime"
        ),
    ]
)

