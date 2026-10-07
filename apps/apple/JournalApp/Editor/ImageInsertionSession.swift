import Foundation
import JournalCore
import SwiftUI

/// One Insert Image: the images chosen are read and stored in the background, then inserted together, in the order
/// chosen, where the caret was (docs/design/several-photos-2026-10-03.md).
@MainActor
final class ImageInsertionSession: ObservableObject {
    private let generation: UUID
    private let store: JournalStore
    private let entryID: UUID
    private let command: (EditorCommand) -> Void
    private var finished = false
    /// Ended by the person or the app without a message: Stop, locking, or another Insert Image.
    private var quiet = false
    private var read = 0
    /// How many of the chosen images have been read, while the wait is long enough to show it.
    @Published private(set) var progress: (done: Int, total: Int)?

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

    /// The same entry is still open in the same library, so it only stopped accepting changes: a connection started,
    /// a sync brought content from a newer version, or it or its journal was deleted.
    private func stayedOpen(in model: AppModel) -> Bool {
        !finished && !Task.isCancelled && generation == model.imageInsertionGeneration && model.store === store
            && model.draft?.id == entryID
    }

    /// Ends the import without a message: Stop, locking, or another Insert Image.
    func cancel() {
        quiet = true
        finished = true
        progress = nil
    }

    /// The person left the entry: nothing more is inserted, and the images not added are mentioned.
    func leave() {
        finished = true
        progress = nil
    }

    func insert(_ data: Data, into model: AppModel) async {
        await insert([{ data }], into: model)
    }

    /// Reads the chosen images two at a time, stores each, and inserts them all once every one has been read. Images
    /// that can't be read or stored are skipped, and one message says how many and why.
    func insert(_ loads: [ImageLoad], into model: AppModel) async {
        guard !loads.isEmpty, isCurrent(in: model) else { return }
        let total = loads.count
        let reveal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, !self.finished else { return }
            self.progress = (self.read, total)
        }
        defer { reveal.cancel() }
        var blocks: [DocumentBlock] = []
        var problems: [ImportedImage.Problem] = []
        await OrderedImageReading.read(loads, width: 2) { result in
            guard self.isCurrent(in: model) else { return false }
            do {
                // A single image is shown at once; several are read back by the editor once inserted.
                guard let block = try await model.importImage(result.get(), showing: total == 1) else { return false }
                blocks.append(block)
            } catch {
                if total == 1 { model.error = error.shown(.saving) }
                problems.append(.of(error))
            }
            self.read += 1
            if self.progress != nil { self.progress = (self.read, total) }
            return self.isCurrent(in: model)
        }
        guard isCurrent(in: model) else {
            if !quiet, !model.locked {
                model.error = stayedOpen(in: model) ? Self.unchangeableMessage(total) : Self.leftMessage(total)
            }
            return
        }
        finished = true
        progress = nil
        for block in blocks { command(.image(block)) }
        if total > 1, let message = Self.problemMessage(problems, of: total) { model.error = message }
        if !blocks.isEmpty { JournalAccessibility.announce(blocks.count == 1 ? "Image added" : "Images added") }
    }

    /// Said when the person leaves the entry before the chosen images were read.
    static func leftMessage(_ total: Int) -> String {
        total == 1
            ? "The image wasn’t added because you left the entry before it finished."
            : "The images weren’t added because you left the entry before they finished."
    }

    /// Said when the entry stays open but can't be changed before the chosen images were read.
    static func unchangeableMessage(_ total: Int) -> String {
        total == 1
            ? "The image wasn’t added because this entry can’t be changed right now."
            : "The images weren’t added because this entry can’t be changed right now."
    }

    /// One message for the images of several that couldn't be added, with their cause when they share one.
    static func problemMessage(_ problems: [ImportedImage.Problem], of total: Int) -> String? {
        guard !problems.isEmpty else { return nil }
        let count =
            problems.count == total
            ? "None of the \(total) images could be added."
            : "\(problems.count) of \(total) images couldn’t be added."
        let cause: String
        switch Set(problems) {
        case [.tooLarge]: cause = "They’re larger than 25 MB."
        case [.unreadable]: cause = "They couldn’t be read."
        case [.unavailable]: cause = "They may still be downloading from iCloud. Try again later."
        default: cause = "Try again, or choose other images."
        }
        return count + " " + cause
    }
}

/// Reads images a few at a time and hands each over in the order chosen, so a long selection uses no more memory
/// than a short one. Cancelling the task that reads cancels the reads.
enum OrderedImageReading {
    /// `each` gets every result in order and returns false to stop; reads that haven't been handed over are then
    /// cancelled. At most `width` images are read ahead of the one being handed over.
    @MainActor static func read(
        _ loads: [ImageLoad], width: Int, _ each: (Result<Data, Error>) async -> Bool
    ) async {
        await withTaskGroup(of: (Int, Result<Data, Error>).self) { group in
            var started = 0
            var handed = 0
            var arrived: [Int: Result<Data, Error>] = [:]
            while handed < loads.count {
                while started < loads.count, started < handed + max(1, width) {
                    let index = started
                    let load = loads[index]
                    group.addTask {
                        do {
                            return (index, .success(try await load()))
                        } catch {
                            return (index, .failure(error))
                        }
                    }
                    started += 1
                }
                guard let (index, result) = await group.next() else { return }
                arrived[index] = result
                while let result = arrived.removeValue(forKey: handed) {
                    handed += 1
                    guard await each(result) else {
                        group.cancelAll()
                        return
                    }
                }
            }
        }
    }
}
