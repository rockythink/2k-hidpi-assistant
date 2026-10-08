// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PixelFit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PixelFit", targets: ["PixelFit"]),
        .executable(name: "PixelFitVirtualDisplayHelper", targets: ["PixelFitVirtualDisplayHelper"])
    ],
    targets: [
        .executableTarget(
            name: "PixelFit",
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
            name: "PixelFitVirtualDisplayHelper",
            path: "NativeVirtualDisplay",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("CoreGraphics")]
        ),
        .testTarget(
            name: "PixelFitTests",
            dependencies: ["PixelFit"],
            path: "Tests"
        )
    ]
)
