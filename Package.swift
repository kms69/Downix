// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DownloadManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Main executable application
        .executable(
            name: "DownloadManager",
            targets: ["DownloadManager"]
        ),
    ],
    dependencies: [
        // Add any external dependencies here
    ],
    targets: [
        .executableTarget(
            name: "DownloadManager",
            dependencies: [],
            path: "DownloadManager/Sources",
            exclude: ["Examples.swift"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
            ]
        ),
        .testTarget(
            name: "DownloadManagerTests",
            dependencies: ["DownloadManager"],
            path: "DownloadManager/Tests",
            exclude: ["TestRunner.swift"]
        ),
    ]
)
