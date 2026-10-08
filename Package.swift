// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HiDPIBuddy",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HiDPIBuddy", targets: ["HiDPIBuddy"]),
        .executable(name: "HiDPIBuddyVirtualDisplayHelper", targets: ["HiDPIBuddyVirtualDisplayHelper"])
    ],
    targets: [
        .executableTarget(
            name: "HiDPIBuddy",
            path: ".",
            exclude: [
                "Tests",
                "README.md",
                "LICENSE",
                "THIRD_PARTY_NOTICES.md",
                "docs",
                "dist",
                "script",
                "Resources",
                "NativeVirtualDisplay",
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
        ),
        .executableTarget(
            name: "HiDPIBuddyVirtualDisplayHelper",
            path: "NativeVirtualDisplay",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]
        ),
        .testTarget(
            name: "HiDPIBuddyTests",
            dependencies: ["HiDPIBuddy"],
            path: "Tests"
        )
    ]
)
