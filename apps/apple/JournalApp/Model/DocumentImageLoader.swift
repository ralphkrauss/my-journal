import Foundation
import ImageIO
import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// Retains only one displayed document's images, and owns every pending read. Photos larger than any editor shows
/// them are kept as smaller copies: a camera photo's original is several megabytes, and an entry can hold dozens.
/// The originals stay in the store for export and sync.
@MainActor
final class DocumentImageLoader: ObservableObject {
    @Published private(set) var images: [UUID: Data] = [:]
    @Published private(set) var loading: Set<UUID> = []
    private(set) var task: Task<Void, Never>?
    private var generation = 0
    private var store: JournalStore?
    private var documentID: UUID?
    private var references: Set<UUID> = []
    /// The longest side, in pixels, of an image as the editor keeps it: more than the widest editor (760 points)
    /// needs at three pixels per point.
    nonisolated static let displayPixels = 2_560

    func update(_ item: JournalItem?, store: JournalStore?, enabled: Bool, retry: Bool = false) {
        guard enabled, let item, let store else {
            clear()
            return
        }
        let order = item.document.attachmentIDs
        let references = Set(order)
        guard retry || self.store !== store || documentID != item.id || self.references != references else { return }
        let kept = self.store === store ? images.filter { references.contains($0.key) } : [:]
        let missing = references.subtracting(kept.keys)
        // Nothing to read: the images and states shown stay as they are.
        if self.store === store, documentID == item.id, self.references == references, missing.isEmpty,
            loading.isEmpty
        {
            return
        }
        task?.cancel()
        generation += 1
        let generation = generation
        self.store = store
        documentID = item.id
        self.references = references
        if kept.count != images.count { images = kept }
        if loading != missing { loading = missing }
        // Images are read a few at a time, in the order the entry shows them, and shown a few at a time rather than
        // one update each.
        let queue = order.filter(missing.contains)
        task = Task { [weak self] in
            await withTaskGroup(of: (UUID, Data?).self) { group in
                var waiting = queue.makeIterator()
                for _ in 0..<4 {
                    if let id = waiting.next() { group.addTask { (id, await Self.load(id, from: store)) } }
                }
                var arrived: [UUID: Data?] = [:]
                var lastDelivery = Date()
                while let (id, shown) = await group.next() {
                    guard !Task.isCancelled, let self, self.isCurrent(generation, store: store, documentID: item.id)
                    else {
                        group.cancelAll()
                        return
                    }
                    arrived.updateValue(shown, forKey: id)
                    if let next = waiting.next() { group.addTask { (next, await Self.load(next, from: store)) } }
                    if Date().timeIntervalSince(lastDelivery) > 0.15 {
                        self.deliver(arrived)
                        arrived = [:]
                        lastDelivery = Date()
                    }
                }
                guard !Task.isCancelled, let self, self.isCurrent(generation, store: store, documentID: item.id)
                else { return }
                self.deliver(arrived)
            }
        }
    }

    private nonisolated static func load(_ id: UUID, from store: JournalStore) async -> Data? {
        await displayCopy(of: try? await store.attachment(id))
    }

    private func isCurrent(_ generation: Int, store: JournalStore, documentID: UUID) -> Bool {
        self.generation == generation && self.store === store && self.documentID == documentID
    }

    private func deliver(_ arrived: [UUID: Data?]) {
        guard !arrived.isEmpty else { return }
        var images = images
        for (id, data) in arrived { images[id] = data }
        self.images = images
        loading.subtract(arrived.keys)
    }

    /// The image as the editor shows it: the original when it's no larger than `displayPixels`, otherwise a copy that
    /// size, upright, with the same size in points. Made off the main thread.
    nonisolated static func displayCopy(of original: Data?) async -> Data? {
        guard let original else { return nil }
        return await Task.detached(priority: .userInitiated) { reduced(original) ?? original }.value
    }

    nonisolated static func reduced(_ original: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(
                original as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            max(width, height) > Double(displayPixels),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: displayPixels,
                ] as CFDictionary)
        else { return nil }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, (opaque ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil)
        else { return nil }
        // The same size in points as the original, so the editor lays it out the same way.
        let longest = Double(max(image.width, image.height))
        let ratio = longest / max(width, height)
        let resolution = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        var options: [CFString: Any] = [
            kCGImagePropertyDPIWidth: resolution * ratio, kCGImagePropertyDPIHeight: resolution * ratio,
        ]
        if opaque { options[kCGImageDestinationLossyCompressionQuality] = 0.9 }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// One inserted image may precede its draft block; the next reference/selection change prunes it. A large photo
    /// is shown from its original until its smaller copy is ready.
    func prime(_ data: Data, id: UUID, documentID: UUID, store: JournalStore) {
        guard self.store === store, self.documentID == documentID else { return }
        var images = images.filter { references.contains($0.key) }
        images[id] = data
        self.images = images
        loading.remove(id)
        let generation = generation
        Task { [weak self] in
            guard let shown = await Self.displayCopy(of: data), shown.count < data.count, let self,
                self.isCurrent(generation, store: store, documentID: documentID), self.images[id] == data
            else { return }
            self.images[id] = shown
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        generation += 1
        store = nil
        documentID = nil
        references = []
        if !images.isEmpty { images = [:] }
        if !loading.isEmpty { loading = [] }
    }

    deinit { task?.cancel() }
}

extension AppModel {
    func updateImageLoading(retry: Bool = false) {
        // Only replacing the library clears images; committing an entry action keeps the open entry's images.
        imageLoader.update(draft, store: store, enabled: !locked && !vaultReplacement, retry: retry)
    }
}
