import XCTest

@testable import JournalCore

final class CodeEntryTests: XCTestCase {
    /// Typed one character at a time, as a person would, or pasted in any form, the code reads as the server shows it.
    func testSetupCodeIsFormattedAsTypedOrPasted() {
        var field = ""
        for character in "fpjs35" { field = CodeEntry.setupCode(field + String(character), previous: field) }
        XCTAssertEqual(field, "FPJ-S35")
        XCTAssertEqual(CodeEntry.setupCode("fpj s35\n", previous: ""), "FPJ-S35")
        XCTAssertEqual(CodeEntry.setupCode("FPJ–S35", previous: ""), "FPJ-S35")
        XCTAssertNil(CodeEntry.setupCodeProblem("fpj-s35"))
        // Pasted over something else, a whole code is formatted too.
        XCTAssertEqual(CodeEntry.setupCode("fpjs35", previous: "23"), "FPJ-S35")
    }

    /// Deleting or editing inside the code is left alone, so the cursor doesn't jump and nothing typed disappears.
    func testOtherEditsAreLeftAsTyped() {
        XCTAssertEqual(CodeEntry.setupCode("FPJ-", previous: "FPJ-S"), "FPJ-")
        XCTAssertEqual(CodeEntry.setupCode("FPJ-S", previous: "FPJ-"), "FPJ-S")
        XCTAssertEqual(CodeEntry.setupCode("FxPJ-S", previous: "FPJ-S"), "FxPJ-S")
        XCTAssertEqual(CodeEntry.pairingCode("123 45", previous: "123 456"), "123 45")
        XCTAssertEqual(CodeEntry.pairingCode("1234567", previous: "123 456"), "123 456 7")
    }

    func testSetupCodeProblemsAreSpecific() {
        XCTAssertEqual(CodeEntry.setupCodeProblem("FPJ-S3"), .length)
        XCTAssertEqual(CodeEntry.setupCodeProblem("FPJS-UR35"), .length, "Eight characters are no longer accepted")
        XCTAssertEqual(CodeEntry.setupCodeProblem("FPJ-S30"), .characters)
        XCTAssertEqual(CodeEntry.setupCodeProblem("FPJ-SÉ5"), .characters)
        XCTAssertTrue(CodeEntry.pairingCodeIsComplete("123 456 789"))
        XCTAssertFalse(CodeEntry.pairingCodeIsComplete("123 456 78"))
    }
}
