// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Lumina - Native, ultra-low-power macOS live wallpaper engine
// Targeting latest macOS (Tahoe / 2026 release) for clean modern APIs and maximum efficiency.
// We can relax the deployment target later if broader compatibility is requested.

let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Lumina", targets: ["Lumina"])
    ],
    dependencies: [
        // Future lightweight dependencies (added as needed):
        // .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        // .package(url: "https://github.com/sindresorhus/Defaults", from: "8.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Lumina",
            dependencies: [
                // "KeyboardShortcuts",
                // "Defaults",
            ],
            path: "Sources/Lumina",
            sources: ["."],   // All .swift under Sources/Lumina and subdirs
            swiftSettings: [
                // Required for @main AppKit/SwiftUI apps in SPM executables.
                // Tells the compiler this module provides its own main entry point
                // via the @main attribute and should be treated as library code.
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "LuminaTests",
            dependencies: ["Lumina"],
            path: "Tests/LuminaTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
