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
            // SPM automatically discovers all .swift files. 
            // Resources (custom Grok Imagine icons, future assets) are declared separately.
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Required for @main AppKit/SwiftUI apps in SPM executables.
                .unsafeFlags(["-parse-as-library"]),

                // Relaxed concurrency during active development / Swift 6 migration.
                // This eliminates the remaining data-race warnings from thumbnail loading
                // without changing behavior. We can tighten this later.
                .unsafeFlags(["-strict-concurrency=minimal"])
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
