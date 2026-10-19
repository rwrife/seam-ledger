// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SeamLedgerStore",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "SeamLedgerStore", targets: ["SeamLedgerStore"]),
    ],
    dependencies: [
        .package(path: "../SeamLedgerKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0"),
    ],
    targets: [
        .target(name: "SeamLedgerStore", dependencies: ["SeamLedgerKit", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SeamLedgerStoreTests", dependencies: ["SeamLedgerStore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Fixtures")]),
    ]
)
