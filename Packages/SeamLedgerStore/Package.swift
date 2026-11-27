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
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(name: "SeamLedgerStore", dependencies: [
            "SeamLedgerKit",
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Crypto", package: "swift-crypto"),
        ]),
        .testTarget(name: "SeamLedgerStoreTests", dependencies: ["SeamLedgerStore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Fixtures")]),
    ]
)
