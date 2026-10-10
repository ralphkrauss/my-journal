import XCTest

/// App Store Connect refuses an iOS upload whose privacy manifest misses a required-reason API the app uses
/// (docs/app-store/app-privacy.md#privacy-manifest). This reads the manifest from the built app that hosts the tests.
final class PrivacyManifestTests: XCTestCase {
    func testTheBuiltAppDeclaresEveryRequiredReasonAPIItUses() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "the manifest is in the app")
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        let declared =
            (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []).reduce(into: [:]) {
                declared, entry in
                if let type = entry["NSPrivacyAccessedAPIType"] as? String {
                    declared[type] = Set(entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
                }
            } as [String: Set<String>]
        // UserDefaults; contentModificationDate (ServerJoining); volumeAvailableCapacityForImportantUsage
        // (ArchiveLimits), checked before an archive is written or restored; no message shows the amount.
        XCTAssertEqual(
            declared,
            [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
                "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
                "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
            ])
    }
}
