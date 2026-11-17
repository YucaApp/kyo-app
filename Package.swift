// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kyo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kyo", targets: ["Kyo"]),
        .library(name: "KyoCore", targets: ["KyoCore"]),
    ],
    targets: [
        // Pure logic: reminder timing, labels, meeting-link detection. No AppKit.
        .target(
            name: "KyoCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app: notch panel, EventKit, timers.
        .executableTarget(
            name: "Kyo",
            dependencies: ["KyoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KyoCoreTests",
            dependencies: ["KyoCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
