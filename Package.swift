// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Promise",
    products: [
        .library(
            name: "Promise",
            targets: ["Promise"]
        ),
    ],
    dependencies: [
        
    ],
    targets: [
        .target(
            name: "Promise",
            dependencies: []
        ),
        .testTarget(
            name: "PromiseTests",
            dependencies: ["Promise"]
        ),
    ]
)
