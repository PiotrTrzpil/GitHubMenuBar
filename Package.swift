// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitHubMenuBar",
    platforms: [
        .macOS(.v13)
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
            ]
        )
    ]
)
