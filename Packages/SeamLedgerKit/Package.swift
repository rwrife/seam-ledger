// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SeamLedgerKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SeamLedgerKit", targets: ["SeamLedgerKit"]),
    ],
    targets: [
        .target(name: "SeamLedgerKit"),
        .testTarget(name: "SeamLedgerKitTests", dependencies: ["SeamLedgerKit"]),
    ]
)
