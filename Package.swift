// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "intervalswellnesssync-hrv-sleep-score-algorithms",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(
            name: "HRVSleepAlgorithms",
            targets: ["HRVSleepAlgorithms"]
        ),
    ],
    targets: [
        .target(
            name: "HRVSleepAlgorithms",
            path: "Sources"
        ),
        .testTarget(
            name: "HRVSleepAlgorithmsTests",
            dependencies: ["HRVSleepAlgorithms"],
            path: "Tests"
        ),
    ]
)
