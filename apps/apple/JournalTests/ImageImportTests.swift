import CoreGraphics
import ImageIO
import JournalCore
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import Journal

@MainActor
final class ImageImportTests: XCTestCase {
    func testImageImportUsesEncodedTypeAndPreservesBytesBeforeRejectingInvalidData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageImport-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let model = AppModel(directory: root)
        model.store = store
        model.draft = JournalItem(kind: "entry")
        for (type, expected) in [(UTType.png, "image/png"), (.jpeg, "image/jpeg"), (.tiff, "image/tiff")] {
            let bytes = try encodedImage(type)
            let imported = await model.addImage(bytes)
            let block = try XCTUnwrap(imported)
            XCTAssertEqual(block.mediaType, expected)
            let stored = try await store.attachment(XCTUnwrap(block.attachmentID))
            XCTAssertEqual(stored, bytes)
        }
        let pendingBefore = try await store.pendingAttachments()
        let draftBefore = model.draft
        let rejected = await model.addImage(Data("Not an image".utf8))
        XCTAssertNil(rejected)
        XCTAssertEqual(model.error, "This file couldn’t be read as an image.")
        let pendingAfter = try await store.pendingAttachments()
        XCTAssertEqual(Set(pendingAfter), Set(pendingBefore))
        XCTAssertEqual(model.draft, draftBefore)
    }

    func testPickerSessionCannotReviveAfterNavigationLockOrStoreReplacement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageSession-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let model = AppModel(directory: root)
        model.store = store
        let original = JournalItem(kind: "template", document: .plain("Keep this text"))
        model.draft = original
        let actions = EditorActions()
        let editor = NativeEditor(
            document: Binding(
                get: { model.draft?.document ?? .plain("") },
                set: { document in
                    guard var draft = model.draft else { return }
                    draft.document = document
                    model.draft = draft
                }),
            itemID: original.id, images: [:], fontSize: 17, editable: true, actions: actions
        ) { _ in nil }
        let coordinator = editor.makeCoordinator()
        let view = JournalTextView(frame: CGRect(x: 0, y: 0, width: 360, height: 500))
        coordinator.view = view
        view.delegate = coordinator
        coordinator.update(editor)
        let bytes = try encodedImage(.png)
        for transition in ["entry", "lock", "store", "cancel"] {
            let session = try XCTUnwrap(ImageInsertionSession(model: model, actions: actions))
            switch transition {
            case "entry": model.draft = JournalItem(kind: "template")
            case "lock":
                model.locked = true
                model.locked = false
            case "store":
                model.store = nil
                model.store = store
            default: session.cancel()
            }
            model.draft = original
            XCTAssertFalse(session.isCurrent(in: model), transition)
            await session.insert(bytes, into: model)
            let pending = try await store.pendingAttachments()
            XCTAssertTrue(pending.isEmpty, transition)
            XCTAssertEqual(model.draft, original)
        }
        let session = try XCTUnwrap(ImageInsertionSession(model: model, actions: actions))
        await session.insert(bytes, into: model)
        let image = try XCTUnwrap(model.draft?.document.blocks.first { $0.kind == "image" })
        let stored = try await store.attachment(XCTUnwrap(image.attachmentID))
        XCTAssertEqual(stored, bytes)
        XCTAssertTrue(model.draft?.document.text.contains("Keep this text") == true)
        XCTAssertFalse(session.isCurrent(in: model))
        let inserted = model.draft
        await session.insert(bytes, into: model)
        XCTAssertEqual(model.draft, inserted)
    }

    /// Writing continues while a picked or pasted image is stored. The image still belongs to the open entry, so it
    /// is returned for insertion instead of being left unused in the store.
    func testAnImageStoredWhileTheEntryChangesIsKept() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageTyping-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let model = AppModel(directory: root)
        model.store = store
        model.draft = JournalItem(kind: "entry", document: .plain("Before"))
        let bytes = try encodedImage(.png)
        let importing = Task { await model.addImage(bytes) }
        // The import runs until it waits for the store; the person keeps typing meanwhile.
        await Task.yield()
        model.draft?.document = .plain("Before, and written while the image was stored")
        let block = await importing.value
        let stored = try await store.attachment(XCTUnwrap(block?.attachmentID))
        XCTAssertEqual(stored, bytes)
        model.draft = JournalItem(kind: "entry")
        let elsewhere = Task { await model.addImage(bytes) }
        await Task.yield()
        model.draft = JournalItem(kind: "entry")
        let discarded = await elsewhere.value
        XCTAssertNil(discarded, "An image isn't added to an entry opened after it was chosen")
    }

    /// Where a photo was taken is removed before it's stored. The image itself, its orientation and capture time stay:
    /// JPEG and HEIC keep their encoded image data, and PNG, which ImageIO has to encode again, loses no pixel.
    func testAddedImagesLoseTheirLocationButKeepTheirPixelsAndOrientation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ImageLocation-" + UUID().uuidString)
        let store = try JournalStore(directory: root, key: VaultCrypto.generateKey())
        addTeardownBlock {
            try await store.close()
            try FileManager.default.removeItem(at: root)
        }
        let model = AppModel(directory: root)
        model.store = store
        model.draft = JournalItem(kind: "entry")
        for type in [UTType.jpeg, .heic, .png] {
            let photo = try photoTaken(at: type)
            XCTAssertNotNil(try properties(photo)[kCGImagePropertyGPSDictionary], "\(type) fixture")
            let added = await model.addImage(photo)
            let block = try XCTUnwrap(added, "\(type)")
            XCTAssertEqual(block.mediaType, type.preferredMIMEType)
            let stored = try await store.attachment(XCTUnwrap(block.attachmentID))
            let kept = try properties(stored)
            XCTAssertNil(kept[kCGImagePropertyGPSDictionary], "\(type)")
            let place = kept[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
            XCTAssertNil(place?[kCGImagePropertyIPTCCity], "\(type)")
            XCTAssertNil(place?[kCGImagePropertyIPTCSubLocation], "\(type)")
            XCTAssertEqual(kept[kCGImagePropertyOrientation] as? Int, 6, "\(type)")
            let exif = kept[kCGImagePropertyExifDictionary] as? [CFString: Any]
            XCTAssertEqual(exif?[kCGImagePropertyExifDateTimeOriginal] as? String, "2026:09:20 12:00:00", "\(type)")
            XCTAssertEqual(try pixels(stored), try pixels(photo), "\(type)")
        }
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    private func pixels(_ data: Data) throws -> Data {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }

    /// A photo with GPS coordinates, place names, an orientation and a capture time.
    private func photoTaken(at type: UTType) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for column in 0..<8 {
            context.setFillColor(CGColor(red: CGFloat(column) / 8, green: 0.5, blue: 1 - CGFloat(column) / 8, alpha: 1))
            context.fill(CGRect(x: column * 8, y: 0, width: 8, height: 48))
        }
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 48.8584, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.2945, kCGImagePropertyGPSLongitudeRef: "E",
            ],
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCCity: "Paris", kCGImagePropertyIPTCSubLocation: "Quai",
            ],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:20 12:00:00"],
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }

    private func encodedImage(_ type: UTType) throws -> Data {
        let context = try XCTUnwrap(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
