import JournalCore
import XCTest

@testable import Journal

/// “Use a Template…” in an empty entry and New Entry from Template on the Templates screen
/// (docs/design/new-entry-template-suggestion.md). A template must never replace writing.
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
        await model.newEntry(blank: true)
        let entry = try XCTUnwrap(model.draft)
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(template: template)
        XCTAssertEqual(model.draft?.id, entry.id, "The same entry stays open")
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.map(\.id), [entry.id], "No second entry")
    }

    func testATypedTitleIsKeptWhenTheBodyIsFilled() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry(blank: true)
        var titled = try XCTUnwrap(model.draft)
        titled.title = "Morning"
        model.updateDraft(titled)
        _ = await model.finishPendingSave()
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(template: template)
        XCTAssertEqual(model.draft?.id, titled.id)
        XCTAssertEqual(model.draft?.title, "Morning")
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    func testWhitespaceIsNothingToLoseSoTheEntryIsFilledInPlace() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry(blank: true)
        try await type(" \n", into: model)
        let entry = try XCTUnwrap(model.draft)
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(template: template)
        XCTAssertEqual(model.draft?.id, entry.id)
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    func testAnEmptiedOlderEntryIsFilledInPlaceAndKeepsItsDate() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry(blank: true)
        try await type("Written, then removed", into: model)
        let id = try XCTUnwrap(model.draft?.id)
        await model.select(nil)
        await model.select(id)
        try await type("", into: model)
        let emptied = try XCTUnwrap(model.draft)
        XCTAssertEqual(model.templateSuggestion(for: emptied), .useTemplate)
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(template: template)
        XCTAssertEqual(model.draft?.id, id)
        XCTAssertEqual(model.draft?.date, emptied.date)
        XCTAssertEqual(model.draft?.document.markdown, template.document.markdown)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    func testWritingBeforeTheChoiceIsKeptAndTheTemplateGoesToANewEntry() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry(blank: true)
        var written = try XCTUnwrap(model.draft)
        written.document = .plain("Already started")
        model.updateDraft(written)
        _ = await model.finishPendingSave()
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(template: template)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.id == written.id }?.document.text, "Already started")
        XCTAssertNotEqual(model.draft?.id, written.id)
    }

    func testAChangeSyncedBeforeTheChoiceIsLeftAloneAndTheTemplateGoesToANewEntry() async throws {
        let (model, store) = try await startedModel()
        await model.newEntry(blank: true)
        let entry = try XCTUnwrap(model.draft)
        // The open draft still looks untouched; only the store has the other device's text.
        try await arrive("Written on the iPhone", in: entry.id, model: model, store: store)
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(template: template)
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.first { $0.id == entry.id }?.document.text, "Written on the iPhone")
        XCTAssertNotEqual(model.draft?.id, entry.id)
        let conflicts = try await store.conflicts()
        XCTAssertTrue(conflicts.isEmpty)
    }

    /// Outside a journal, the entry goes to Settings ▸ Default Journal, not to the journal shown before Templates
    /// (docs/design/default-journal.md).
    func testAnEntryStartedFromTheTemplatesScreenOpensInTheDefaultJournal() async throws {
        let (model, store) = try await startedModel()
        await model.createJournal("Work")
        let work = try XCTUnwrap(model.journals.first { $0.title == "Work" })
        let other = try XCTUnwrap(model.journals.first { $0.id != work.id })
        model.chooseDefaultJournal(work.id)
        await model.switchJournal(other.id)
        await model.showCollection(templates: true)
        var template = try XCTUnwrap(model.templates.first)
        await model.select(template.id)
        template.document = .plain("Edited just now")
        model.updateDraft(template)

        await model.newEntry(fromTemplate: template.id)
        XCTAssertFalse(model.showingTemplates, "Templates is left")
        XCTAssertEqual(model.selectedJournalID, work.id)
        let entry = try XCTUnwrap(model.draft)
        XCTAssertEqual(entry.kind, "entry", "The new entry is open")
        XCTAssertEqual(entry.journalID, work.id)
        XCTAssertEqual(entry.document.text, "Edited just now", "The template as it was just written")
        let savedTemplate = try await store.item(template.id)
        XCTAssertEqual(savedTemplate?.document.text, "Edited just now")
        let stored = try await entries(in: store)
        XCTAssertEqual(stored.count, 1)
    }

    func testWithoutASelectedJournalTheEntryGoesToTheDefaultJournal() async throws {
        let (model, _) = try await startedModel()
        let fallback = try XCTUnwrap(model.defaultJournal)
        await model.showCollection(templates: true)
        model.selectedJournalID = nil
        let template = try XCTUnwrap(model.templates.first)

        await model.newEntry(fromTemplate: template.id)
        XCTAssertEqual(model.draft?.journalID, fallback.id)
        XCTAssertEqual(model.selectedJournalID, fallback.id, "The list shows where the entry went")
        XCTAssertFalse(model.showingTemplates)
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
        return (model, try XCTUnwrap(model.store))
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
