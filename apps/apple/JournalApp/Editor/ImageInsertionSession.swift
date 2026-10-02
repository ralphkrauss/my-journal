import Foundation
import JournalCore

@MainActor
final class ImageInsertionSession {
    private let generation: UUID
    private let store: JournalStore
    private let entryID: UUID
    private let command: (EditorCommand) -> Void
    private var finished = false

    init?(model: AppModel, actions: EditorActions) {
        guard model.canEdit, let store = model.store, let draft = model.draft,
            let command = actions.beginFormatting?()
        else { return nil }
        generation = model.imageInsertionGeneration
        self.store = store
        entryID = draft.id
        self.command = command
    }

    /// The editor places the image where it was asked for even if the text changed meanwhile, so the session
    /// itself follows the entry, the vault and the model's insertion generation rather than the document.
    func isCurrent(in model: AppModel) -> Bool {
        !finished && !Task.isCancelled && generation == model.imageInsertionGeneration
            && model.store === store && model.draft?.id == entryID && model.canEdit
    }

    func cancel() { finished = true }

    func insert(_ data: Data, into model: AppModel) async {
        guard isCurrent(in: model), let block = await model.addImage(data) else { return }
        await Task.yield()
        guard isCurrent(in: model) else { return }
        finished = true
        command(.image(block))
    }
}
