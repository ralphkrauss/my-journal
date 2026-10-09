// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JournalCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "JournalCore", targets: ["JournalCore"]),
        .executable(name: "JournalProbe", targets: ["JournalProbe"]),
        .executable(name: "JournalMeasure", targets: ["JournalMeasure"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
    ],
    targets: [
        .target(name: "CJournalCrypto", publicHeadersPath: "include"),
        // The system zlib's CRC-32 for the archive container and SQLite's defensive mode for inspecting archived
        // databases: both ship with the operating system, so this adds no dependency.
        .target(
            name: "CJournalArchive", publicHeadersPath: "include",
            linkerSettings: [.linkedLibrary("z"), .linkedLibrary("sqlite3")]),
        .target(
            name: "JournalCore",
            dependencies: [
                "CJournalCrypto", "CJournalArchive", .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Markdown", package: "swift-markdown"),
            ]),
        .executableTarget(name: "JournalProbe", dependencies: ["JournalCore"]),
        .executableTarget(name: "JournalMeasure", dependencies: ["JournalCore"]),
        .testTarget(name: "JournalCoreTests", dependencies: ["JournalCore", "CJournalArchive"]),
    ]
)
