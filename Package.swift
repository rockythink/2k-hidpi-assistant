// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HiDPIBuddy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HiDPIBuddy", targets: ["HiDPIBuddy"])
    ],
    targets: [
        .executableTarget(
            name: "HiDPIBuddy",
            path: ".",
            exclude: [
                "Tests",
                "README.md",
                "dist",
                "script",
                ".codex",
                ".build"
            ],
            sources: [
                "App",
                "Views",
                "Models",
                "Stores",
                "Services",
                "Support"
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals")
            ]
        )
    ]
)
