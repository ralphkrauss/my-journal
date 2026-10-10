import CryptoKit
import Foundation

// The rules that settle a record changed on two devices without asking (protocol/conflicts.md, conflicts v1). Only
// decoded versions go in, so every client can implement the same function and check it against
// protocol/conformance/records/conflict-resolution-v1.json. Nothing here reads a clock or a database.

/// One version of a record: what it decodes to and the exact plaintext it was decoded from.
public struct ConflictSide: Sendable, Equatable {
    public let item: JournalItem
    /// The plaintext record JSON as authenticated, as this device holds it. Copy identities hash these exact bytes.
    public let plaintext: Data

    public init(item: JournalItem, plaintext: Data) {
        self.item = item
        self.plaintext = plaintext
    }
    /// Reads `plaintext` the way a stored record is read; content this version can't fully read is kept as it is.
    public init(plaintext: Data, id: UUID, kind: String) {
        let decoded = try? PortableRecord.decode(plaintext)
        if let decoded, decoded.id == id, decoded.kind == kind {
            item = decoded
        } else {
            item = PortableRecord.unreadable(plaintext, id: id, kind: kind)
        }
        self.plaintext = plaintext
    }
    /// A version this app can't change without losing content (row 1).
    var isHeld: Bool { !item.isSupported || !["journal", "entry", "template"].contains(item.kind) }
    var isMarker: Bool { item.isPermanentlyDeleted }
}

/// What settling a conflict produces. L is this device's version, R the other one.
public enum ConflictOutcome: Equatable, Sendable {
    /// Row 1: a version this app can't read. Nothing is created, written or sent until it can be read.
    case held
    /// Row 3: an entry or template whose content differs. This device's version stays the record; `copy` is the other
    /// version as a separate entry or template, with an identity every device derives alike.
    case keepBoth(copy: JournalItem)
    /// Row 2: the same content. `record` is L's content with the merged deletion state. With `adoptsOther` it equals R
    /// in every field but the modified time, so R's bytes become the record and nothing is sent.
    case sameContent(record: JournalItem, adoptsOther: Bool)
    /// Row 4: an entry or template against a marker. The marker is the record; `parked` is the edited version as a
    /// new entry or template in Recently Deleted.
    case parked(parked: JournalItem, markerIsLocal: Bool)
    /// Row 5: two markers. R's marker is the record.
    case twoMarkers
    /// Row 6: a journal renamed or changed on both. L's content stays with the merged deletion state, R goes to
    /// history. `otherName` is R's name when the names differ.
    case journal(record: JournalItem, otherName: String?)
    /// Row 7: a journal against a marker. The marker is the record; no journal is created.
    case journalMarker(markerIsLocal: Bool, name: String)
}

public enum ConflictResolution {
    /// The first row of the table in protocol/conflicts.md that matches.
    public static func resolve(local: ConflictSide, other: ConflictSide, ids: ConflictCopyIdentity) -> ConflictOutcome {
        if local.isHeld || other.isHeld { return .held }
        let lhs = local.item
        let rhs = other.item
        let markers = (local.isMarker, other.isMarker)
        // Row 2 is for versions that both have content: a marker is only ever its own record or the other's.
        if markers == (false, false), sameContent(local, other) {
            return sameContentOutcome(local: lhs, other: rhs)
        }
        switch markers {
        case (true, true): return .twoMarkers
        case (true, false), (false, true):
            let markerIsLocal = markers.0
            let edited = markerIsLocal ? other : local
            let marker = markerIsLocal ? lhs : rhs
            if lhs.kind == "journal" { return .journalMarker(markerIsLocal: markerIsLocal, name: edited.item.title) }
            return .parked(parked: parked(edited, marker: marker, ids: ids), markerIsLocal: markerIsLocal)
        case (false, false):
            guard lhs.kind == "journal" else { return .keepBoth(copy: copy(of: other, ids: ids)) }
            var record = lhs
            (record.deletedAt, record.deletedWithJournal) = deletion(of: lhs, and: rhs)
            return .journal(record: record, otherName: sameText(lhs.title, rhs.title) ? nil : rhs.title)
        }
    }

    private static func sameContentOutcome(local: JournalItem, other: JournalItem) -> ConflictOutcome {
        var merged = local
        (merged.deletedAt, merged.deletedWithJournal) = deletion(of: local, and: other)
        var comparable = merged
        comparable.modifiedAt = other.modifiedAt
        comparable.restoredFromDeletionID = other.restoredFromDeletionID
        comparable.storedVersion = other.storedVersion
        return .sameContent(record: merged, adoptsOther: comparable == other)
    }

    // MARK: Equality of content (3.2.1)

    /// Whether two versions hold the same content. A false "same" would lose an edit silently and a false "different"
    /// only makes a copy, so this is strict: field by field, with the whole document compared as a JSON value.
    public static func sameContent(_ first: ConflictSide, _ second: ConflictSide) -> Bool {
        let lhs = first.item
        let rhs = second.item
        guard lhs.kind == rhs.kind, sameText(lhs.title, rhs.title) else { return false }
        switch lhs.kind {
        case "journal":
            return lhs.defaultTemplateID == rhs.defaultTemplateID
        case "entry":
            return lhs.date == rhs.date && lhs.journalID == rhs.journalID && lhs.archivedAt == rhs.archivedAt
                && sameDocument(first.plaintext, second.plaintext)
        case "template":
            return lhs.date == rhs.date && lhs.archivedAt == rhs.archivedAt
                && sameDocument(first.plaintext, second.plaintext)
        default:
            return false
        }
    }
    /// Strings are equal when they have the same Unicode scalars. Swift's `==` also equates canonically equivalent
    /// texts (a composed and a decomposed é), which another client's ordinal comparison does not, and a false "same"
    /// would lose an edit.
    static func sameText(_ first: String, _ second: String) -> Bool {
        first.unicodeScalars.elementsEqual(second.unicodeScalars)
    }
    /// The `document` members of two record plaintexts as JSON values: objects unordered, arrays ordered, strings by
    /// code points, and numbers by kind and value. Two devices seal the same content differently, so bytes are never
    /// compared.
    static func sameDocument(_ first: Data, _ second: Data) -> Bool {
        guard let one = document(of: first), let other = document(of: second) else { return false }
        return sameJSON(one, other)
    }
    private static func document(of plaintext: Data) -> NSDictionary? {
        guard let object = (try? JSONSerialization.jsonObject(with: plaintext)) as? [String: Any] else { return nil }
        return object["document"] as? NSDictionary
    }
    /// Whether two parsed JSON values are the same value. Foundation's own equality would equate `true` with 1 and 1
    /// with 1.0, and compare keys and strings as canonically equivalent text in places; a false "same" would lose an
    /// edit, so a boolean is never a number, an integer is never a number with a fraction or an exponent, and every
    /// string and key is compared by its Unicode scalars.
    static func sameJSON(_ first: Any, _ second: Any) -> Bool {
        switch (first, second) {
        case (let one as NSDictionary, let other as NSDictionary):
            guard one.count == other.count else { return false }
            let others = Dictionary(
                uniqueKeysWithValues: other.map { (String(describing: $0.key).unicodeScalars.map(\.value), $0.value) })
            return one.allSatisfy { entry in
                guard let match = others[String(describing: entry.key).unicodeScalars.map(\.value)] else {
                    return false
                }
                return sameJSON(entry.value, match)
            }
        case (let one as NSArray, let other as NSArray):
            return one.count == other.count && zip(one, other).allSatisfy { sameJSON($0, $1) }
        case (let one as NSString, let other as NSString):
            return sameText(one as String, other as String)
        case (let one as NSNumber, let other as NSNumber):
            return sameNumber(one, other)
        case (is NSNull, is NSNull):
            return true
        default:
            return false
        }
    }
    private static func sameNumber(_ first: NSNumber, _ second: NSNumber) -> Bool {
        enum Kind { case boolean, integer, fractional }
        func kind(_ number: NSNumber) -> Kind {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .boolean }
            return CFNumberIsFloatType(number) ? .fractional : .integer
        }
        return kind(first) == kind(second) && first.isEqual(to: second)
    }

    // MARK: Deletion state (3.2.2)

    /// `(deletedAt, deletedWithJournal)` is one unit and no clock is read. With one version deleted, that version's
    /// pair is taken. With both, the pair that is deleted with its journal if either is, else R's. With neither, none.
    /// `deletedWithJournal` is only set by writers before 1.0, so that clause matters for legacy entries only.
    static func deletion(of local: JournalItem, and other: JournalItem) -> (Date?, Bool) {
        switch (local.deletedAt, other.deletedAt) {
        case (nil, nil): return (nil, false)
        case (.some(let deleted), nil): return (deleted, local.deletedWithJournal)
        case (nil, .some(let deleted)): return (deleted, other.deletedWithJournal)
        case (.some, .some):
            if local.deletedWithJournal { return (local.deletedAt, true) }
            return (other.deletedAt, other.deletedWithJournal)
        }
    }

    // MARK: The other version as a copy (3.3)

    /// The other version of an entry or template as a separate record. Everything is the other version's, so a copy in
    /// Recently Deleted stays there; only the title says what it is. The identity is derived from the other version's
    /// exact text, so every device that finds the conflict makes the same copy.
    static func copy(of other: ConflictSide, ids: ConflictCopyIdentity) -> JournalItem {
        var item = other.item
        item.id = ids.copyID(.copy, record: other.item.id, plaintext: other.plaintext)
        item.title = copyTitle(of: other.item)
        item.restoredFromDeletionID = nil
        item.storedVersion = nil
        return item
    }
    /// "{title} (other version)": the other version's title, or when it is empty or only white space (Unicode
    /// White_Space) the title the lists show for it: the first line of the text that is not empty, cut at 60 extended
    /// grapheme clusters, or the catalog's name when that line is only white space or there is none. Always appended,
    /// never detected: a copy of a copy reads twice. Catalog text (`messages.conflict.copyTitle`); clients never parse
    /// it.
    public static func copyTitle(of item: JournalItem) -> String {
        let title: String
        if !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = item.title
        } else if let line = item.document.firstLine, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = String(line.prefix(60))
        } else {
            title = item.kind == "template" ? "Untitled Template" : "New Entry"
        }
        return "\(title) (other version)"
    }

    // MARK: Parking (3.4)

    /// The edited version of an entry or template as a new record in Recently Deleted. Its identity is derived from the
    /// edited version's text, so every device that finds the conflict makes the same record. The title and content are
    /// unchanged; it is not a version of anything. `deletedAt` is the marker's time, the same on every device.
    static func parked(_ edited: ConflictSide, marker: JournalItem, ids: ConflictCopyIdentity) -> JournalItem {
        var item = edited.item
        item.id = ids.copyID(.park, record: edited.item.id, plaintext: edited.plaintext)
        item.deletedAt = marker.permanentlyDeletedAt
        item.deletedWithJournal = false
        item.restoredFromDeletionID = nil
        item.storedVersion = nil
        return item
    }
}

// MARK: Copy identity (3.3.1)

/// How the identity of a copy or a parked entry is derived. The same copy is made once, however many devices find the
/// conflict; the key hides the link between a copy and its source from a server.
public struct ConflictCopyIdentity: Sendable {
    public enum Label: String, Sendable {
        /// A copy of the other version (row 3).
        case copy = "conflict-copy"
        /// An edit parked next to a permanent deletion (row 4).
        case park = "conflict-park"
    }
    static let info = "journal:v1:conflict-copy-id"
    private let subkey: SymmetricKey

    /// `vaultKey` is the 32-byte vault key of an encrypted library. Libraries without encryption (version 1.0 only)
    /// derived the key from a public constant; this version never opens them.
    public init(vaultKey: Data) {
        subkey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: vaultKey), salt: Data(), info: Data(Self.info.utf8),
            outputByteCount: 32)
    }
    /// The derivation key, for the conformance vectors.
    public var subkeyBytes: Data { subkey.withUnsafeBytes { Data($0) } }

    /// The identity: the first 16 bytes of HMAC-SHA-256 over the label, the record's lower-case identity and the
    /// lower-case hex SHA-256 of the exact plaintext text, with the version nibble 8 and the variant bits set.
    public func copyID(_ label: Label, record: UUID, plaintext: Data) -> UUID {
        let digest = SHA256.hash(data: plaintext).map { String(format: "%02x", $0) }.joined()
        let message = "\(label.rawValue)\n\(record.uuidString.lowercased())\n\(digest)"
        var bytes = Array(Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: subkey)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
