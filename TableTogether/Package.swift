// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "TableTogether",
    platforms: [
        .iOS(.v26),
        .macCatalyst(.v18),
        .tvOS(.v26)
    ],
    products: [
        .library(
            name: "TableTogetherLib",
            targets: ["TableTogetherLib"]
        ),
    ],
    targets: [
        .target(
            name: "TableTogetherLib",
            path: "Sources",
            resources: [
                .process("CoreData/TableTogether.xcdatamodeld")
            ]
        ),
        .testTarget(
            name: "TableTogetherTests",
            dependencies: ["TableTogetherLib"],
            path: "Tests"
        ),
    ]
)
