// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RumbaMacApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "RumbaMacApp", targets: ["RumbaMacApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.24.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .executableTarget(
            name: "RumbaMacApp",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources/RumbaMacApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
