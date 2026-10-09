import ImageIO
import JournalCore
import SwiftUI
import os

struct ImageDescriptionsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let entryID: UUID
    @State private var images: [DocumentBlock]
    @State private var descriptions: [UUID: String]
    @FocusState private var focusedImage: UUID?
    @State private var busy = false
    @State private var completed = false
    @State private var reloading = false
    @State private var needsEntrySave = false
    @State private var invalidated = false
    @State private var error: String?
    @State private var confirmingReload = false
    @State private var operation: Task<Void, Never>?
    /// The descriptions were saved as the journals locked.
    @State private var savedBeforeLocking = false
    @State private var previews = ImagePreviews()
    @Environment(\.displayScale) private var displayScale
    init(entry: JournalItem) {
        entryID = entry.id
        let images = entry.document.imageBlocks
        _images = State(initialValue: images)
        _descriptions = State(
            initialValue: Dictionary(
                images.map { ($0.id, $0.imageDescription ?? "") },
                uniquingKeysWith: { first, _ in first }))
    }
    private var dirty: Bool { images.contains { descriptions[$0.id] != ($0.imageDescription ?? "") } }
    private var eligible: Bool { model.canDescribeImages(in: entryID) }
    var body: some View {
        Group {
            #if os(iOS)
                NavigationStack {
                    content.navigationTitle("Image Descriptions").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { cancelButton }
                            ToolbarItem(placement: .confirmationAction) { doneButton }
                        }
                }
            #else
                VStack(spacing: 0) {
                    Text("Image Descriptions").font(.title2.bold()).padding(.top, 24)
                    content
                    Divider()
                    HStack {
                        cancelButton
                        Spacer()
                        doneButton
                    }.padding()
                }.frame(minWidth: 360, idealWidth: 460, minHeight: 400, idealHeight: 540)
            #endif
        }
        .interactiveDismissDisabled(busy || dirty)
        // Typed descriptions are saved, as Done would, before My Journal locks and closes the sheet.
        .savesBeforeLocking { await saveBeforeLocking() }
        .onDisappear { operation?.cancel() }
        .onAppear {
            restoreKeptDescriptions()
            checkEligibility()
        }
        .onValueChange(of: eligible) { available in
            if !available { checkEligibility() }
        }
        .onValueChange(of: model.locked) { locked in
            if locked {
                // Descriptions that couldn't be saved first stay in memory, never lost (LockSaving.swift).
                if dirty && !completed && !savedBeforeLocking {
                    model.keepUnsavedImageDescriptions(
                        UnsavedImageDescriptions(
                            entryID: entryID, expectedImages: images, descriptions: descriptions))
                }
                operation?.cancel()
                focusedImage = nil
                images = []
                descriptions = [:]
                error = nil
                confirmingReload = false
                dismiss()
            }
        }
        .onValueChange(of: error) { value in
            if let value, !model.locked { JournalAccessibility.announce(value) }
        }
        .confirmationDialog("Discard description changes?", isPresented: $confirmingReload, titleVisibility: .visible) {
            Button("Keep Editing", role: .cancel) {}
            Button("Reload Images", role: .destructive) { reload() }
        }
    }
    private var cancelButton: some View {
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(busy || completed)
    }
    private var doneButton: some View {
        Button("Done") {
            if completed || !dirty { dismiss() } else { save() }
        }.disabled(busy || (!completed && dirty && (!eligible || invalidated || needsEntrySave)))
    }
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !model.locked {
                        Text("Describe what matters in each image. Descriptions help people using VoiceOver.")
                            .foregroundStyle(.secondary)
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, block in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(images.count == 1 ? "Image" : "Image \(index + 1)").font(.headline)
                                preview(block, ordinal: index + 1)
                                TextField(
                                    "Description",
                                    text: Binding(
                                        get: { descriptions[block.id] ?? "" },
                                        set: { describe(block.id, as: $0) }), axis: .vertical
                                )
                                .lineLimit(1...3)
                                .submitLabel(index == images.count - 1 ? .done : .next)
                                .onSubmit { advance(from: block.id) }
                                .focused($focusedImage, equals: block.id)
                                .id(block.id)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Image \(index + 1) description")
                                .disabled(busy || completed)
                            }
                        }
                        if let error { Text(error).foregroundStyle(.secondary).textSelection(.enabled) }
                        if busy { ProgressView(reloading ? "Loading Images…" : "Saving Descriptions…") }
                        if !completed {
                            Button("Copy Descriptions") { copyDescriptions() }.disabled(busy)
                            if !needsEntrySave && (error != nil || invalidated) {
                                Button("Reload Images") {
                                    if dirty { confirmingReload = true } else { reload() }
                                }.disabled(busy || !eligible)
                                if !invalidated && eligible { Button("Try Again") { save() }.disabled(busy) }
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onValueChange(of: focusedImage) { id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
    @ViewBuilder private func preview(_ block: DocumentBlock, ordinal: Int) -> some View {
        let label = "Image \(ordinal). \(descriptions[block.id] ?? "")"
        if let id = block.attachmentID, let bytes = model.imageData[id],
            let image = previews.image(id, bytes, maximumPixels: 280 * displayScale, scale: displayScale)
        {
            image.resizable().scaledToFit().frame(maxWidth: 280, maxHeight: 160).accessibilityLabel(label)
        } else if let id = block.attachmentID, model.imageLoader.loading.contains(id) {
            ProgressView("Loading Image…").accessibilityLabel("Loading Image. \(label)")
        } else {
            Label("Image Unavailable", systemImage: "photo").foregroundStyle(.secondary)
                .accessibilityLabel("\(label) Image Unavailable")
        }
    }
    /// A description is one line. The field wraps long text, but Return moves on to the next description, as caption
    /// fields do, and pasted line breaks become spaces, so the field always shows what will be saved.
    private func describe(_ id: UUID, as text: String) {
        let current = descriptions[id] ?? ""
        if text.count == current.count + 1, text.filter({ !$0.isNewline }) == current {
            advance(from: id)
        } else {
            descriptions[id] = ImageDescription.singleLine(text)
        }
    }
    /// Moves focus to the next description, or ends editing after the last one.
    private func advance(from id: UUID) {
        guard focusedImage == id, let index = images.firstIndex(where: { $0.id == id }) else { return }
        focusedImage = images.indices.contains(index + 1) ? images[index + 1].id : nil
    }
    private func copyDescriptions() {
        let text = images.enumerated().map { index, block in
            "Image \(index + 1)\n\(descriptions[block.id] ?? "")"
        }.joined(separator: "\n\n")
        #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        #else
            UIPasteboard.general.string = text
        #endif
    }
    private func reload() {
        guard eligible, !busy else { return }
        busy = true
        reloading = true
        operation = Task {
            defer {
                busy = false
                reloading = false
                checkEligibility()
            }
            do {
                let current = try await model.reloadImageDescriptionEntry(entryID)
                guard !model.locked else { return }
                images = current.document.imageBlocks
                descriptions = Dictionary(
                    images.map { ($0.id, $0.imageDescription ?? "") },
                    uniquingKeysWith: { first, _ in first })
                invalidated = false
                error = nil
            } catch is CancellationError {} catch {
                if !model.locked {
                    if case JournalError.saveRequired = error { needsEntrySave = true }
                    self.error = error.shown(.reading)
                }
            }
        }
    }
    private func checkEligibility() {
        guard !eligible, !busy, !completed, !model.locked else { return }
        invalidated = true
        error = "This entry is no longer available for editing. Your description changes are still here."
    }
    private func saveBeforeLocking() async {
        guard dirty, !busy, !completed, eligible, !invalidated else { return }
        do {
            _ = try await model.saveImageDescriptions(
                entryID: entryID, expectedImages: images, descriptions: descriptions)
            savedBeforeLocking = true
        } catch {
            // The lock keeps them in memory instead.
            Logger(subsystem: "org.privatejournal", category: "image-descriptions").error(
                "Could not save image descriptions before locking.")
        }
    }
    /// Descriptions a lock closed this sheet on before they were saved appear again, still to be saved with Done.
    private func restoreKeptDescriptions() {
        guard let kept = model.takeUnsavedImageDescriptions(for: entryID, images: images) else { return }
        for block in images {
            if let text = kept[block.id] { descriptions[block.id] = text }
        }
    }
    private func save() {
        guard !busy, !completed, eligible, !invalidated, !needsEntrySave else { return }
        busy = true
        error = nil
        let expected = images
        let values = descriptions
        operation = Task {
            defer {
                busy = false
                checkEligibility()
            }
            do {
                let refreshed = try await model.saveImageDescriptions(
                    entryID: entryID, expectedImages: expected,
                    descriptions: values)
                guard !model.locked else { return }
                completed = true
                if refreshed {
                    dismiss()
                } else {
                    error = "The descriptions were saved, but couldn’t be displayed. Reopen My Journal to try again."
                }
            } catch is CancellationError {} catch {
                guard !model.locked else { return }
                if error is ImageDescriptionError || error is JournalLifecycleError { invalidated = true }
                if case JournalError.saveRequired = error { invalidated = true }
                if case JournalError.saveRequired = error { needsEntrySave = true }
                self.error = error.shown(.saving)
            }
        }
    }
}

/// Previews decoded once at the size they're shown, not from the full image on every redraw. An image's bytes never
/// change for its identifier, so a decoded preview is kept while the sheet is open.
@MainActor
private final class ImagePreviews {
    private var decoded: [UUID: Image] = [:]
    func image(_ id: UUID, _ data: Data, maximumPixels: CGFloat, scale: CGFloat) -> Image? {
        if let image = decoded[id] { return image }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels, kCGImageSourceShouldCacheImmediately: true,
        ]
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = Image(preview, scale: scale, label: Text(""))
        decoded[id] = image
        return image
    }
}
