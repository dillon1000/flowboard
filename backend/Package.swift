// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "FlowboardServer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "App", targets: ["Run"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.1"),
        .package(
            url: "https://github.com/soto-project/soto-core.git",
            exact: "7.14.0"
        ),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.5.1")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "SotoSignerV4", package: "soto-core"),
                .product(name: "Vapor", package: "vapor")
            ]
        ),
        .executableTarget(name: "Run", dependencies: [.target(name: "App")]),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor")
            ]
        )
    ]
)
