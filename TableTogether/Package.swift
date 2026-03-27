// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TableTogether",
    platforms: [
        .iOS(.v26),
        .tvOS(.v26)
    ],
    products: [
        .library(
            name: "TableTogether",
            targets: ["TableTogether"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TableTogether",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "TableTogetherTests",
            dependencies: ["TableTogether"],
            path: "Tests"
        ),
    ]
)
