import CoreGraphics
import Foundation
import ImageIO
import JournalCore
import UniformTypeIdentifiers

/// A reproducible library shaped like ten years of heavy daily writing. All content is generated from a fixed seed;
/// nothing comes from a real journal. The seeded directory holds the encrypted library, its synthetic key, a manifest
/// the measurements read, and the change log a server would hold for it (encrypted payloads only).
struct SyntheticLibrary {
    struct Shape: Codable {
        var journals = 20
        var entries = 4_000
        var longEntries = 50
        var templates = 10
        /// Small photos spread over the library. Their count, not their size, drives library-wide work; the disk
        /// space a camera-sized copy of each would need is left out on purpose.
        var libraryPhotos = 4_950
        /// Camera-sized photos (12 MP JPEG) in one entry, for memory while showing images.
        var cameraPhotos = 50
        /// Entries edited on two other devices, which leaves versions in their history.
        var historyEntries = 300
        var openConflicts = 3
        /// The same kinds of content in a small library, for measuring what doesn't depend on its size.
        static let small = Shape(
            journals: 3, entries: 40, longEntries: 2, templates: 4, libraryPhotos: 20, cameraPhotos: 3,
            historyEntries: 5, openConflicts: 1)
    }
    struct Manifest: Codable {
        var shape: Shape
        var journalID: UUID
        var normalEntryID: UUID
        var longEntryID: UUID
        var photoEntryID: UUID
        /// Query text and how many entries contain it in their title or text.
        var searchTerms: [String: Int]
        var serverID: String
        var cursor: Int64
        var markdownBytes: Int
        var libraryPhotoBytes: Int
        var cameraPhotoBytes: Int
    }

    let directory: URL
    var shape = Shape()
    private var random = SeededRandom(seed: 0x4A6F_7572_6E61_6C21)
    private var cursor: Int64 = 0
    private var log: [RemoteChange] = []
    private let deviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000a") ?? UUID()
    private let deviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000b") ?? UUID()
    static let start = Date(timeIntervalSince1970: 1_475_000_000)

    init(directory: URL) { self.directory = directory }

    var libraryURL: URL { directory.appendingPathComponent("library", isDirectory: true) }
    var keyURL: URL { directory.appendingPathComponent("synthetic-key") }
    var manifestURL: URL { directory.appendingPathComponent("manifest.json") }
    var logURL: URL { directory.appendingPathComponent("server-log.json") }

    mutating func seed() async throws -> Manifest {
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw MeasurementError.existingFixture }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = try VaultCrypto.generateKey()
        try key.write(to: keyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        let store = try JournalStore(directory: libraryURL, key: key)
        let journals = (0..<shape.journals).map { index in
            JournalItem(
                kind: "journal", title: index == 0 ? "Daily" : Words.title(&random, words: 2),
                date: Self.start.addingTimeInterval(Double(index) * 60))
        }
        for journal in journals { try await store.save(journal) }
        for index in 0..<shape.templates {
            let template =
                index < BuiltInTemplates.all.count
                ? BuiltInTemplates.all[index]
                : JournalItem(
                    kind: "template", title: Words.title(&random, words: 2),
                    document: JournalDocument(markdown: markdown(words: 60, images: [])))
            try await store.save(template)
        }
        var photos = try await addPhotos(to: store)
        let content = try await addEntries(to: store, journals: journals, photos: &photos)
        try await acknowledgeEverything(in: store)
        let other = try JournalStore(directory: directory.appendingPathComponent("other-device"), key: key)
        try await addHistory(to: store, from: other, entries: content.historyIDs)
        try await other.close()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("other-device"))
        let serverID = "synthetic-server"
        try await store.setSetting("server-id", value: Data(serverID.utf8))
        try await store.apply([], cursor: cursor)
        try await store.close()
        try JournalCoding.encoder().encode(log).write(to: logURL)
        let manifest = Manifest(
            shape: shape, journalID: journals[0].id, normalEntryID: content.normalID, longEntryID: content.longID,
            photoEntryID: content.photoEntryID, searchTerms: content.searchTerms, serverID: serverID, cursor: cursor,
            markdownBytes: content.markdownBytes, libraryPhotoBytes: photos.libraryBytes,
            cameraPhotoBytes: photos.cameraBytes)
        try JournalCoding.encoder().encode(manifest).write(to: manifestURL)
        return manifest
    }

    struct Photos {
        var library: [UUID]
        var camera: [UUID]
        var libraryBytes = 0
        var cameraBytes = 0
    }

    private mutating func addPhotos(to store: JournalStore) async throws -> Photos {
        let small = try (0..<16).map { try Self.jpeg(width: 320, height: 240, variant: $0) }
        let camera = try (0..<5).map { try Self.jpeg(width: 4_032, height: 3_024, variant: $0) }
        var photos = Photos(library: [], camera: [])
        for index in 0..<shape.libraryPhotos {
            let bytes = small[index % small.count]
            photos.library.append(try await store.addAttachment(bytes))
            photos.libraryBytes += bytes.count
        }
        for index in 0..<shape.cameraPhotos {
            let bytes = camera[index % camera.count]
            photos.camera.append(try await store.addAttachment(bytes))
            photos.cameraBytes += bytes.count
        }
        return photos
    }

    struct Content {
        var normalID: UUID
        var longID: UUID
        var photoEntryID: UUID
        var historyIDs: [UUID]
        var searchTerms: [String: Int]
        var markdownBytes: Int
    }

    private mutating func addEntries(to store: JournalStore, journals: [JournalItem], photos: inout Photos)
        async throws -> Content
    {
        let count = shape.entries
        var longIndices = Set<Int>()
        while longIndices.count < shape.longEntries { longIndices.insert(random.next(in: 0..<count)) }
        let photoEntry = count - 2
        let normalEntry = count - 1
        var counts: [String: Int] = ["orchid": 0, "lighthouse": 0, "meeting": 0, "zeppelin": 0]
        var ids: [UUID] = []
        var markdownBytes = 0
        var longID: UUID?
        for index in 0..<count {
            let long = longIndices.contains(index) && index != photoEntry && index != normalEntry
            let words = long ? random.next(in: 20_000..<50_001) : random.next(in: 300..<1_501)
            var images: [UUID] = []
            if index == photoEntry {
                images = photos.camera
            } else if !photos.library.isEmpty, random.next(in: 0..<100) < 40 {
                let taken = min(photos.library.count, random.next(in: 1..<6))
                images = Array(photos.library.suffix(taken))
                photos.library.removeLast(taken)
            }
            var text = markdown(words: words, images: images)
            if index == count / 2 { text += "\n\nThe orchid by the window finally bloomed.\n" }
            if random.next(in: 0..<100) < 6 { text += "\n\nWe walked to the lighthouse after dinner.\n" }
            if index == photoEntry || index == normalEntry { text = markdown(words: 700, images: images) }
            let journal = index == normalEntry || index == photoEntry ? journals[0] : pickJournal(journals)
            let titled = random.next(in: 0..<100) < 75
            var entry = JournalItem(
                kind: "entry", journalID: journal.id, title: titled ? Words.title(&random, words: 4) : "",
                document: JournalDocument(markdown: text),
                date: Self.start.addingTimeInterval(Double(index) * 78_840 + Double(random.next(in: 0..<3_600))))
            if index == normalEntry { entry.title = "Normal entry" }
            if index == photoEntry { entry.title = "Photos from the coast" }
            try await store.save(entry)
            ids.append(entry.id)
            if long, longID == nil { longID = entry.id }
            markdownBytes += text.utf8.count
            let searchable = (entry.title + "\n" + text).lowercased()
            for term in counts.keys where searchable.contains(term) { counts[term, default: 0] += 1 }
        }
        let history = Array(ids.filter { _ in random.next(in: 0..<100) < 10 }.prefix(shape.historyEntries))
        return Content(
            normalID: ids[normalEntry], longID: longID ?? ids[0], photoEntryID: ids[photoEntry], historyIDs: history,
            searchTerms: counts, markdownBytes: markdownBytes)
    }

    private mutating func pickJournal(_ journals: [JournalItem]) -> JournalItem {
        // Most writing goes to a few journals, as in real use.
        let roll = random.next(in: 0..<100)
        if roll < 45 { return journals[0] }
        if roll < 65 { return journals[1] }
        if roll < 80 { return journals[2] }
        return journals[random.next(in: 3..<journals.count)]
    }

    /// Marks everything as synchronized with the server, as on a device that has been in use for years.
    private mutating func acknowledgeEverything(in store: JournalStore) async throws {
        for pending in try await store.pending() {
            cursor += 1
            let receipt = RemoteChange(
                cursor: cursor, recordId: pending.recordID, revision: pending.baseRevision + 1, kind: pending.kind,
                payload: pending.payload, deviceId: deviceA, modifiedAt: Self.start)
            try await store.acknowledge(pending, receipt: receipt)
            log.append(receipt)
        }
        for id in try await store.pendingAttachments() { try await store.acknowledgeAttachment(id) }
    }

    /// Entries edited on another device while this one also changed them: each review keeps both versions in history.
    /// A few reviews are left open.
    private mutating func addHistory(to store: JournalStore, from other: JournalStore, entries: [UUID]) async throws {
        for (offset, id) in entries.enumerated() {
            guard var local = try await store.item(id) else { continue }
            var remote = local
            remote.document = JournalDocument(markdown: local.document.markdown + "\n\nAdded on the iPad.\n")
            remote.modifiedAt = local.modifiedAt.addingTimeInterval(60)
            try await other.save(remote)
            guard let remotePending = try await other.pending().first(where: { $0.recordID == id }) else { continue }
            local.document = JournalDocument(markdown: local.document.markdown + "\n\nAdded on the Mac.\n")
            try await store.save(local)
            cursor += 1
            let change = RemoteChange(
                cursor: cursor, recordId: id, revision: 2, kind: "entry", payload: remotePending.payload,
                deviceId: deviceB, modifiedAt: remote.modifiedAt)
            try await store.apply([change], cursor: cursor)
            log.append(change)
            guard offset >= shape.openConflicts,
                let conflict = try await store.conflicts().first(where: { $0.id == id })
            else { continue }
            try await store.resolve(conflict, choice: .local)
            guard let pending = try await store.pending().first(where: { $0.recordID == id }) else { continue }
            cursor += 1
            let receipt = RemoteChange(
                cursor: cursor, recordId: id, revision: pending.baseRevision + 1, kind: "entry",
                payload: pending.payload, deviceId: deviceA, modifiedAt: Self.start)
            try await store.acknowledge(pending, receipt: receipt)
            log.append(receipt)
        }
    }

    /// Markdown with the mix of structure people use while writing: paragraphs, headings, lists, tasks, emphasis and
    /// links, with images between paragraphs.
    private mutating func markdown(words: Int, images: [UUID]) -> String {
        var parts: [String] = []
        var remaining = words
        var pending = images
        while remaining > 0 {
            let roll = random.next(in: 0..<100)
            let length = min(remaining, random.next(in: 30..<120))
            if roll < 6 {
                parts.append("## " + Words.title(&random, words: 3))
            } else if roll < 12 {
                let items = (0..<random.next(in: 2..<5)).map { _ in "- " + Words.sentence(&random, words: 8) }
                parts.append(items.joined(separator: "\n"))
                remaining -= 20
            } else if roll < 15 {
                let items = (0..<3).map { index in
                    (index == 0 ? "- [x] " : "- [ ] ") + Words.sentence(&random, words: 5)
                }
                parts.append(items.joined(separator: "\n"))
                remaining -= 15
            } else {
                parts.append(Words.paragraph(&random, words: length))
                remaining -= length
            }
            if let image = pending.first, random.next(in: 0..<100) < 30 || remaining <= 0 {
                parts.append("![A photo](attachments/" + image.uuidString.lowercased() + ")")
                pending.removeFirst()
            }
        }
        for image in pending { parts.append("![A photo](attachments/" + image.uuidString.lowercased() + ")") }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// A JPEG with smooth gradients and fine noise, so it compresses like a photo rather than a flat image.
    static func jpeg(width: Int, height: Int, variant: Int) throws -> Data {
        var generator = SeededRandom(seed: UInt64(variant + 1) * 0x9E37_79B9)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let noise = UInt8(generator.next(in: 0..<24))
                pixels[offset] = UInt8((x * 200 / width + variant * 13) % 256) &+ noise
                pixels[offset + 1] = UInt8((y * 180 / height + variant * 29) % 256) &+ noise
                pixels[offset + 2] = UInt8(((x + y) * 120 / (width + height) + 60) % 256) &+ noise
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw MeasurementError.resourceUnavailable }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw MeasurementError.resourceUnavailable }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MeasurementError.resourceUnavailable }
        return output as Data
    }
}

/// A small deterministic generator (SplitMix64), so every run produces the same library.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
    mutating func next(in range: Range<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}

enum Words {
    static let common = """
        the day morning evening walk work coffee tea friend family garden rain sun light window book page letter \
        meeting project plan idea note list call message train station city street river bridge park tree leaf \
        season summer winter autumn spring weekend holiday kitchen dinner lunch breakfast bread soup market music \
        song piano guitar class lesson question answer problem solution design draft review team colleague manager \
        client report email deadline schedule calendar travel airport hotel beach mountain trail forest lake ocean \
        wave boat harbor island village road car bike run swim yoga sleep dream memory photo camera picture story \
        chapter novel poem film theatre museum gallery painting colour shape detail pattern habit routine goal \
        progress change decision reason feeling mood energy calm quiet noise laugh smile worry hope plan quick slow \
        long short early late small large warm cold bright dark clear careful simple honest gentle busy tired happy \
        grateful curious patient steady thought reflection lesson moment week month year today tomorrow yesterday \
        again always never often sometimes almost enough together alone outside inside between before after during
        """
        .split(whereSeparator: { $0.isWhitespace }).map(String.init)

    static func word(_ random: inout SeededRandom) -> String { common[random.next(in: 0..<common.count)] }

    static func title(_ random: inout SeededRandom, words: Int) -> String {
        (0..<words).map { _ in word(&random) }.joined(separator: " ").capitalized
    }

    static func sentence(_ random: inout SeededRandom, words: Int) -> String {
        let text = (0..<words).map { _ in word(&random) }.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    /// A paragraph with occasional emphasis and links.
    static func paragraph(_ random: inout SeededRandom, words: Int) -> String {
        var sentences: [String] = []
        var remaining = words
        while remaining > 0 {
            let length = min(remaining, random.next(in: 6..<18))
            var sentence = self.sentence(&random, words: length)
            let roll = random.next(in: 0..<100)
            if roll < 5 {
                sentence = "**" + sentence.dropLast() + "**."
            } else if roll < 9 {
                sentence = "*" + sentence.dropLast() + "*."
            } else if roll < 11 {
                sentence += " See [the notes](https://example.com/notes)."
            }
            sentences.append(sentence)
            remaining -= length
        }
        return sentences.joined(separator: " ")
    }
}
