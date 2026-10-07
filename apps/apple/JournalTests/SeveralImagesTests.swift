import ImageIO
import JournalCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import Journal

/// Several images chosen at once are read in the background and inserted together, in the order chosen, as one undo
/// step; what can't be added is said once; Stop, locking and leaving the entry insert nothing
/// (docs/design/several-photos-2026-10-03.md).
@MainActor
final class SeveralImagesTests: XCTestCase {
    func testImagesArriveInTheChosenOrderAsOneUndoStepAndFailuresAreSaidOnce() async throws {
        let (harness, model, store) = try await setUp(markdown: "Before\n\nAfter")
        harness.caret(at: ("Before" as NSString).length)
        let pictures = try (1...3).map { try png(width: $0 * 10) }
        let loads: [ImageLoad] = [
            slow(pictures[0], seconds: 0.3), slow(pictures[1], seconds: 0.05),
            { throw ImportedImage.Problem.unavailable }, { Data("Not an image".utf8) },
            slow(pictures[2], seconds: 0.15),
        ]
        let session = try XCTUnwrap(ImageInsertionSession(model: model, actions: harness.actions))
        await session.insert(loads, into: model)
        harness.settle()

        let images = harness.document.blocks.filter { $0.kind == "image" }
        XCTAssertEqual(images.count, 3)
        for (block, picture) in zip(images, pictures) {
            let stored = try await store.attachment(XCTUnwrap(block.attachmentID))
            XCTAssertEqual(stored, picture, "The images keep the order they were chosen in.")
        }
        XCTAssertEqual(model.error, "2 of 5 images couldn’t be added. Try again, or choose other images.")
        XCTAssertTrue(harness.document.markdown.hasPrefix("Before\n\n!["), harness.document.markdown)
        XCTAssertTrue(harness.document.markdown.hasSuffix("After"), harness.document.markdown)
        // One empty line between consecutive images, as after a single one.
        let markdown = harness.document.markdown
        XCTAssertFalse(markdown.contains(")!["), markdown)
        XCTAssertEqual(markdown.components(separatedBy: ")\n\n![").count, 3, markdown)

        harness.undoManager?.undo()
        harness.settle()
        XCTAssertEqual(harness.document.markdown, "Before\n\nAfter", "One Undo removes every image of one choice.")
    }

    func testStopLockAndLeavingInsertNothingAndOnlyLeavingIsMentioned() async throws {
        for ending in ["stop", "lock", "leave"] {
            let (harness, model, _) = try await setUp(markdown: "Text")
            harness.caret(at: 4)
            let session = try XCTUnwrap(ImageInsertionSession(model: model, actions: harness.actions))
            let loads: [ImageLoad] = [slow(try png(width: 10), seconds: 0), slow(try png(width: 20), seconds: 5)]
            let importing = Task { await session.insert(loads, into: model) }
            try await Task.sleep(for: .milliseconds(700))
            XCTAssertEqual(session.progress?.done, 1, "The wait shows how far it got.")
            if ending == "stop" {
                for (scheme, size) in [(ColorScheme.light, DynamicTypeSize.large), (.dark, .accessibility5)] {
                    let notice = ImageImportNotice(session: session) {}.background(.background)
                        .environment(\.colorScheme, scheme).dynamicTypeSize(size)
                    if let shot = await NativeTestPreview.capture(
                        notice, name: "Adding images, \(scheme), \(size)", height: 200)
                    {
                        add(shot)
                    }
                }
            }
            switch ending {
            case "stop": session.cancel()
            case "lock": model.locked = true
            default: session.leave()
            }
            importing.cancel()
            await importing.value
            XCTAssertEqual(harness.document.markdown, "Text", ending)
            XCTAssertEqual(
                model.error, ending == "leave" ? ImageInsertionSession.leftMessage(2) : nil, ending)
        }
    }

    /// An entry can stop accepting changes without the person leaving it, which the message must not say.
    func testAnEntryThatBecomesReadOnlyMeanwhileIsNotReportedAsLeft() async throws {
        let (harness, model, _) = try await setUp(markdown: "Text")
        harness.caret(at: 4)
        let session = try XCTUnwrap(ImageInsertionSession(model: model, actions: harness.actions))
        let load = slow(try png(width: 10), seconds: 0.3)
        let importing = Task { await session.insert([load], into: model) }
        try await Task.sleep(for: .milliseconds(50))
        model.draft?.deletedAt = Date()
        await importing.value
        XCTAssertEqual(harness.document.markdown, "Text")
        XCTAssertEqual(model.error, ImageInsertionSession.unchangeableMessage(1))
        XCTAssertEqual(
            ImageInsertionSession.unchangeableMessage(2),
            "The images weren’t added because this entry can’t be changed right now.")

        model.error = nil
        model.draft?.deletedAt = nil
        let another = try XCTUnwrap(ImageInsertionSession(model: model, actions: harness.actions))
        let slowLoad = slow(try png(width: 10), seconds: 0.3)
        let leaving = Task { await another.insert([slowLoad], into: model) }
        try await Task.sleep(for: .milliseconds(50))
        model.draft = JournalItem(kind: "template")
        await leaving.value
        XCTAssertEqual(model.error, ImageInsertionSession.leftMessage(1), "Another entry is open: the person left.")
    }

    func testTypingElsewhereMeanwhileKeepsThePersonsCaret() async throws {
        let (harness, model, _) = try await setUp(markdown: "First\n\nSecond")
        harness.caret(at: 5)
        let session = try XCTUnwrap(ImageInsertionSession(model: model, actions: harness.actions))
        let load = slow(try png(width: 10), seconds: 0.3)
        let importing = Task { await session.insert([load], into: model) }
        harness.caret(at: harness.text.length)
        harness.type(" more")
        await importing.value
        harness.settle()
        XCTAssertTrue(harness.document.markdown.hasPrefix("First\n\n!["), harness.document.markdown)
        XCTAssertTrue(harness.document.markdown.hasSuffix("Second more"), harness.document.markdown)
        XCTAssertEqual(harness.selection, NSRange(location: harness.text.length, length: 0), "The caret stays put.")
    }

    // MARK: - Fixtures

    private func setUp(markdown: String) async throws -> (EditorHarness, AppModel, JournalStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SeveralImages-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        let harness = EditorHarness(markdown: markdown)
        addTeardownBlock { @MainActor in
            harness.close()
            try? await store.close()
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(directory: root)
        model.store = store
        model.draft = JournalItem(kind: "template", document: harness.document)
        return (harness, model, store)
    }

    private func slow(_ data: Data, seconds: Double) -> ImageLoad {
        {
            try await Task.sleep(for: .seconds(seconds))
            return data
        }
    }

    private func png(width: Int) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: width, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: 8))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
