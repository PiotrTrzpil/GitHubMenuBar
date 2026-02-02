// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitHubMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitHubMenuBar", targets: ["GitHubMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "GitHubMenuBar",
            path: "GitHubMenuBar",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "GitHubMenuBarTests",
            path: "Tests"
        )
    ]
)
