// swift-tools-version:6.0
import PackageDescription

// SeamLedgerStore — persistence layer for SeamLedger (GRDB/SQLite stub in M1).
// Pure domain storage package, Linux-testable by design.
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
    ],
    targets: [
        .target(name: "SeamLedgerStore", dependencies: ["SeamLedgerKit"]),
        .testTarget(name: "SeamLedgerStoreTests", dependencies: ["SeamLedgerStore"]),
    ]
)
