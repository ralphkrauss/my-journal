import JournalCore
import XCTest

@testable import Journal

#if os(iOS)
    import SwiftUI
    import UIKit
#endif

/// “Use a Template…” in an empty entry, from the link and from File ▸ Use a Template…
/// (docs/design/new-entry-template-suggestion.md, docs/design/1-1-library-simplifications.md, M). A template must
/// never replace writing, and choosing one never creates an entry.
@MainActor
final class TemplateSuggestionTests: XCTestCase {
    func testTheLinkShowsWithTheBodyPlaceholder() {
        let empty = JournalItem(kind: "entry", journalID: UUID())
        var spacedTitle = empty
        spacedTitle.title = "  "
        var titled = empty
        titled.title = "M"
        var written = empty
        written.document = .plain("Today")
        var returns = empty
        returns.document = .plain("\n\n")
        var picture = empty
        picture.document = JournalDocument(blocks: [DocumentBlock(kind: "image")])
        let template = JournalItem(kind: "template", title: "")
        let cases: [Case] = [
            Case("empty", empty, expected: .useTemplate),
            Case("a whitespace-only title", spacedTitle, expected: .useTemplate),
            Case("a typed title, the body still empty", titled, expected: .useTemplate),
            Case("body text", written, expected: .hidden),
            Case("a body of only newlines, where the caret would overlap it", returns, expected: .hidden),
            Case("an image", picture, expected: .hidden),
            Case("a template", template, expected: .hidden),
            Case("not editable", empty, canEdit: false, expected: .hidden),
            Case("no templates", empty, hasTemplates: false, expected: .hidden),
        ]
        for rule in cases {
            let state = TemplateSuggestion.resolve(
                entry: rule.entry, hasTemplates: rule.hasTemplates, canEdit: rule.canEdit)
            XCTAssertEqual(state, rule.expected, rule.name)
        }
    }

    func testChoosingATemplateFillsTheEmptyNewEntryInPlace() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        let template = try XCTUnwrap(model.templates.first)

        let result = await model.useTemplate(template, in: entry.id)
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(model.draft?.id, entry.id, "The same entry stays open")
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.map(\.id), [entry.id], "No second entry")
    }

    func testATypedTitleIsKeptWhenTheBodyIsFilled() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        var titled = try XCTUnwrap(model.draft)
        titled.title = "Morning"
        model.updateDraft(titled)
        _ = await model.finishPendingSave()
        let template = try XCTUnwrap(model.templates.first)

        let result = await model.useTemplate(template, in: titled.id)
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(model.draft?.id, titled.id)
        XCTAssertEqual(model.draft?.title, "Morning")
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    func testWhitespaceIsNothingToLoseSoTheEntryIsFilledInPlace() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        try await type(" \n", into: model)
        let entry = try XCTUnwrap(model.draft)
        let template = try XCTUnwrap(model.templates.first)

        let result = await model.useTemplate(template, in: entry.id)
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(model.draft?.id, entry.id)
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    func testAnEmptiedOlderEntryIsFilledInPlaceAndKeepsItsDate() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        try await type("Written, then removed", into: model)
        let id = try XCTUnwrap(model.draft?.id)
        await model.select(nil)
        await model.select(id)
        try await type("", into: model)
        let emptied = try XCTUnwrap(model.draft)
        XCTAssertEqual(model.templateSuggestion(for: emptied), .useTemplate)
        let template = try XCTUnwrap(model.templates.first)

        let result = await model.useTemplate(template, in: id)
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(model.draft?.id, id)
        XCTAssertEqual(model.draft?.date, emptied.date)
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    /// Choosing after the entry gained text changes nothing, creates nothing, and says why in the alert.
    func testWritingBeforeTheChoiceIsKeptAndNothingIsCreated() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        var written = try XCTUnwrap(model.draft)
        written.document = .plain("Already started")
        model.updateDraft(written)
        _ = await model.finishPendingSave()
        let template = try XCTUnwrap(model.templates.first)

        let result = await model.useTemplate(template, in: written.id)
        XCTAssertEqual(result, .entryChanged)
        XCTAssertEqual(model.error, "This entry changed, so the template wasn’t added.")
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.map(\.id), [written.id], "No second entry")
        XCTAssertEqual(stored.first?.document.text, "Already started")
        XCTAssertEqual(model.draft?.id, written.id)
    }

    func testAChangeSyncedBeforeTheChoiceIsLeftAloneAndNothingIsCreated() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        // The open draft still looks untouched; only the store has the other device's text.
        try await arrive("Written on the iPhone", in: entry.id, model: model, store: store)
        let template = try XCTUnwrap(model.templates.first)

        let result = await model.useTemplate(template, in: entry.id)
        XCTAssertEqual(result, .entryChanged)
        XCTAssertEqual(model.error, "This entry changed, so the template wasn’t added.")
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first { $0.id == entry.id }?.document.text, "Written on the iPhone")
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
    }

    /// An entry that was closed meanwhile is left alone: the chooser just closes, with nothing to say.
    func testChoosingForAnEntryThatIsNoLongerOpenChangesNothingAndSaysNothing() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        let template = try XCTUnwrap(model.templates.first)
        await model.select(nil)

        let result = await model.useTemplate(template, in: entry.id)
        XCTAssertEqual(result, .entryClosed)
        XCTAssertNil(model.error)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(stored.first?.document.text, "")
    }

    /// File ▸ Use a Template… is enabled exactly when the link in the empty entry is shown.
    func testTheMenuCommandFollowsTheLink() async throws {
        let (model, _) = try await startedModel()
        XCTAssertFalse(model.canUseTemplate, "No entry is open")
        await model.newEntry()
        XCTAssertTrue(model.canUseTemplate)
        XCTAssertEqual(model.templateSuggestion(for: try XCTUnwrap(model.draft)), .useTemplate)
        try await type("Started", into: model)
        XCTAssertFalse(model.canUseTemplate)
        XCTAssertEqual(model.templateSuggestion(for: try XCTUnwrap(model.draft)), .hidden)
    }

    /// A journal written by 1.0 may name a default template. New Entry ignores it and every journal write keeps it,
    /// so a 1.0 device on the same library still has its setting.
    func testNewEntryIgnoresAJournalsStoredDefaultTemplateAndRenamingKeepsIt() async throws {
        let (model, store) = try await startedModel()
        let template = try XCTUnwrap(model.templates.first)
        let journalID = try XCTUnwrap(model.selectedJournalID)
        let storedJournal = try await store.item(journalID)
        var journal = try XCTUnwrap(storedJournal)
        journal.defaultTemplateID = template.id
        try await store.save(journal)
        try await model.refresh()

        await model.newEntry()
        let entry = try XCTUnwrap(model.draft)
        XCTAssertEqual(entry.journalID, journalID)
        XCTAssertEqual(entry.document.text, "", "The entry is empty, not the template")
        XCTAssertTrue(model.canUseTemplate, "The template is one tap away in the entry")

        model.changeJournal(journalID, name: "Renamed")
        await model.journalEditTask?.value
        let renamed = try await store.item(journalID)
        XCTAssertEqual(renamed?.title, "Renamed")
        XCTAssertEqual(renamed?.defaultTemplateID, template.id)
    }

    // MARK: Support

    private struct Case {
        let name: String
        let entry: JournalItem
        var hasTemplates = true
        var canEdit = true
        let expected: TemplateSuggestion

        init(
            _ name: String, _ entry: JournalItem, hasTemplates: Bool = true, canEdit: Bool = true,
            expected: TemplateSuggestion
        ) {
            self.name = name
            self.entry = entry
            self.hasTemplates = hasTemplates
            self.canEdit = canEdit
            self.expected = expected
        }
    }

    private func type(_ text: String, into model: AppModel) async throws {
        var draft = try XCTUnwrap(model.draft)
        draft.document = .plain(text)
        model.updateDraft(draft)
        let saved = await model.finishPendingSave()
        XCTAssertTrue(saved)
    }

    private var revision: Int64 = 100

    private func startedModel() async throws -> (AppModel, JournalStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = AppModel(directory: root)
        addTeardownBlock { @MainActor in
            try? await model.store?.close()
            try? Keychain.remove(model.keyAccount)
            try? FileManager.default.removeItem(at: root)
        }
        await model.start()
        model.confirmRecovery()
        // A new library has no templates; the person saved one.
        let store = try XCTUnwrap(model.store)
        try await store.save(
            JournalItem(
                kind: "template", title: "Daily",
                document: JournalDocument(markdown: "# What went well?\n\n# What will I carry into tomorrow?")))
        try await model.refresh()
        return (model, store)
    }

    private func entries(in store: JournalStore) async throws -> [JournalItem] {
        try await store.items().filter { $0.kind == "entry" && $0.deletedAt == nil && !$0.isPermanentlyDeleted }
    }

    /// Stores another device's version as sync does, without refreshing the view.
    private func arrive(_ text: String, in id: UUID, model: AppModel, store: JournalStore) async throws {
        let current = try await store.item(id)
        var edited = try XCTUnwrap(current)
        edited.document = .plain(text)
        while let pending = try await store.pending().first(where: { $0.recordID == id }) {
            try await store.acknowledge(
                pending,
                receipt: RemoteChange(
                    cursor: 1, recordId: id, revision: pending.baseRevision + 1, kind: pending.kind,
                    payload: pending.payload, deviceId: UUID(), modifiedAt: Date()))
        }
        revision += 1
        let sealed = try VaultCrypto.seal(
            PortableRecord.encode(edited), key: XCTUnwrap(model.masterKey),
            context: VaultCrypto.recordContext(id: id, kind: "entry"))
        let change = RemoteChange(
            cursor: revision, recordId: id, revision: revision, kind: "entry", payload: sealed.base64EncodedString(),
            deviceId: UUID(), modifiedAt: Date())
        try await store.apply([change], cursor: revision)
    }
}
