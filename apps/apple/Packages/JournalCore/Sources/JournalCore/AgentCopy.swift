import CryptoKit
import Foundation

/// What every device of the library knows about an agent's grant: its name, the client it was approved for, the
/// journals it may read, when access ends and the key of its copy (protocol/agent-access-server.md). The server keeps it
/// sealed like a record. Version 2 adds "all journals"; version 1 (a list of journals) still opens.
public struct AgentCopySettings: Codable, Sendable, Equatable {
    public static let formatVersion = 2
    public var version: Int
    public var name: String
    public var clientName: String
    /// Every journal, including ones created later.
    public var allJournals: Bool
    /// The chosen journals when not all, including ones this device doesn't have.
    public var journalIds: [UUID]
    public var expiresAt: Date?
    /// The 32-byte key the copy's keys are derived from.
    public var key: Data

    public init(
        name: String, clientName: String, allJournals: Bool = false, journalIDs: Set<UUID>, expiresAt: Date?, key: Data
    ) {
        version = Self.formatVersion
        self.name = name
        self.clientName = clientName
        self.allJournals = allJournals
        journalIds = allJournals ? [] : journalIDs.sorted { $0.uuidString < $1.uuidString }
        self.expiresAt = expiresAt
        self.key = key
    }
    public var journalIDs: Set<UUID> { Set(journalIds) }
    /// Whether the agent may read this journal (while it's live).
    public func shares(_ journal: UUID) -> Bool { allJournals || journalIds.contains(journal) }
    public func hasExpired(at date: Date = Date()) -> Bool { expiresAt.map { $0 <= date } ?? false }

    private enum CodingKeys: String, CodingKey {
        case version, name, clientName, journals, journalIds, expiresAt, key
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        name = try container.decode(String.self, forKey: .name)
        clientName = try container.decode(String.self, forKey: .clientName)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        key = try container.decode(Data.self, forKey: .key)
        if version == 1 {
            allJournals = false
            journalIds = try container.decode([UUID].self, forKey: .journalIds)
        } else if (try? container.decode(String.self, forKey: .journals)) == "all" {
            allJournals = true
            journalIds = []
        } else {
            allJournals = false
            journalIds = try container.decode([UUID].self, forKey: .journals)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encode(clientName, forKey: .clientName)
        if version == 1 {
            try container.encode(journalIds, forKey: .journalIds)
        } else if allJournals {
            try container.encode("all", forKey: .journals)
        } else {
            try container.encode(journalIds, forKey: .journals)
        }
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(key, forKey: .key)
    }
}

/// One item of an agent's copy: a shared journal's name, or one entry's readable text.
public struct AgentCopyItem: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case journal, entry }
    public var kind: Kind
    public var id: UUID
    public var name: String?
    public var journalId: UUID?
    public var title: String?
    public var date: Date?
    public var archivedAt: Date?
    public var text: String?

    public static func journal(id: UUID, name: String) -> Self {
        Self(kind: .journal, id: id, name: name)
    }
    public static func entry(
        id: UUID, journalID: UUID, title: String, date: Date, archivedAt: Date?, text: String
    ) -> Self {
        Self(kind: .entry, id: id, journalId: journalID, title: title, date: date, archivedAt: archivedAt, text: text)
    }
}

/// An item sealed for upload: its ID, content digest and payload.
public struct SealedAgentCopyItem: Sendable, Equatable {
    public let id: String
    public let digest: String
    public let payload: String
}

/// The keys of one grant's copy, derived from its copy key.
public struct AgentCopyKeys: Sendable {
    let encryption: SymmetricKey
    let identity: SymmetricKey

    public init(_ key: Data) throws {
        guard key.count == 32 else { throw JournalError.invalidData }
        let input = SymmetricKey(data: key)
        encryption = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input, info: Data("journal:v1:agent-copy:encryption".utf8), outputByteCount: 32)
        identity = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: input, info: Data("journal:v1:agent-copy:item-id".utf8), outputByteCount: 32)
    }
    /// The ID of a record's item. It doesn't reveal the record's ID to the server.
    public func itemID(recordID: UUID) -> String {
        truncated(Data("journal:v1:agent-item:\(recordID.uuidString.lowercased())".utf8))
    }
    func digest(_ plaintext: Data) -> String {
        truncated(Data("journal:v1:agent-digest:".utf8) + plaintext)
    }
    private func truncated(_ message: Data) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: identity)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
    }
}

/// The formats of agent access through the server (protocol/agent-access-server.md).
public enum AgentCopyCrypto {
    static func settingsContext(grantID: UUID) -> String {
        "journal:v1:agent-metadata:\(grantID.uuidString.lowercased())"
    }
    static func itemContext(grantID: UUID, itemID: String) -> String {
        "journal:v1:agent-copy:\(grantID.uuidString.lowercased()):\(itemID)"
    }
    static func grantContext(grantID: UUID) -> String {
        "journal:v1:agent-grant:\(grantID.uuidString.lowercased())"
    }
    /// Seals a grant's settings like a record of this library: encrypted under the vault key.
    public static func sealSettings(
        _ settings: AgentCopySettings, grantID: UUID, vaultKey: Data
    ) throws -> String {
        try VaultCrypto.seal(
            JournalCoding.encoder().encode(settings), key: vaultKey, context: settingsContext(grantID: grantID)
        ).base64EncodedString()
    }
    public static func openSettings(
        _ sealed: String, grantID: UUID, vaultKey: Data
    ) throws -> AgentCopySettings {
        guard let data = Data(base64Encoded: sealed) else { throw JournalError.invalidData }
        let plaintext = try VaultCrypto.open(data, key: vaultKey, context: settingsContext(grantID: grantID))
        let settings = try JournalCoding.decoder().decode(AgentCopySettings.self, from: plaintext)
        guard (1...AgentCopySettings.formatVersion).contains(settings.version), settings.key.count == 32,
            settings.allJournals || !settings.journalIds.isEmpty
        else { throw JournalError.invalidData }
        return settings
    }
    /// Wraps the copy key under a one-time secret for the server, which keeps the secret only until the agent's
    /// authorization code is redeemed and then wraps the key under each token's own secret.
    public static func wrapCopyKey(_ key: Data, secret: Data, grantID: UUID) throws -> Data {
        guard key.count == 32, secret.count == 32 else { throw JournalError.invalidData }
        let wrapKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: secret), info: Data("journal:v1:agent-grant-wrap".utf8),
            outputByteCount: 32)
        let sealed = try AES.GCM.seal(
            key, using: wrapKey, authenticating: Data(grantContext(grantID: grantID).utf8))
        guard let combined = sealed.combined else { throw JournalError.invalidData }
        return combined
    }
    public static func seal(_ item: AgentCopyItem, grantID: UUID, keys: AgentCopyKeys) throws -> SealedAgentCopyItem {
        let identifier = keys.itemID(recordID: item.id)
        let plaintext = try JournalCoding.encoder().encode(item)
        let sealed = try AES.GCM.seal(
            plaintext, using: keys.encryption,
            authenticating: Data(itemContext(grantID: grantID, itemID: identifier).utf8))
        guard let combined = sealed.combined else { throw JournalError.invalidData }
        return SealedAgentCopyItem(
            id: identifier, digest: keys.digest(plaintext), payload: combined.base64EncodedString())
    }
    /// Opens an item of the copy: it must authenticate at its position and name the record its ID came from.
    public static func open(_ payload: String, itemID: String, grantID: UUID, keys: AgentCopyKeys) throws
        -> AgentCopyItem
    {
        guard let data = Data(base64Encoded: payload) else { throw JournalError.invalidData }
        let plaintext = try AES.GCM.open(
            AES.GCM.SealedBox(combined: data), using: keys.encryption,
            authenticating: Data(itemContext(grantID: grantID, itemID: itemID).utf8))
        let item = try JournalCoding.decoder().decode(AgentCopyItem.self, from: plaintext)
        guard keys.itemID(recordID: item.id) == itemID else { throw JournalError.invalidData }
        return item
    }
}

/// The text of an entry as agents read it.
enum AgentCopyText {
    /// Matches the data of a `data:` URI, after its media type and parameters.
    private static let embeddedData = try? NSRegularExpression(
        pattern: #"(data:[^,\s"'()<>]{0,200},)[^\s"'()<>]+"#, options: .caseInsensitive)
    /// Entries kept as Markdown source, and raw HTML, can hold images as `data:` URIs, which are long and meaningless
    /// as text, so their data is replaced with a placeholder. What is stored is never changed.
    static func readable(_ document: JournalDocument) -> String {
        let text = document.text
        guard let embeddedData, text.range(of: "data:", options: .caseInsensitive) != nil else { return text }
        return embeddedData.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1[data omitted]")
    }
}

/// A name an agent's client chose for itself, as the app shows it: line breaks become spaces, control and formatting
/// characters (such as bidirectional overrides, which could reorder text) are removed, and it's one line of at most
/// 40 characters.
public enum AgentDisplayName {
    public static func clean(_ name: String) -> String {
        let scalars = name.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            if scalar.properties.isWhitespace { return " " }
            let category = scalar.properties.generalCategory
            return category == .control || category == .format ? nil : scalar
        }
        let single = String(String.UnicodeScalarView(scalars)).split(separator: " ").joined(separator: " ")
        guard !single.isEmpty else { return "An agent" }
        return single.count > 40 ? String(single.prefix(40)).trimmingCharacters(in: .whitespaces) + "…" : single
    }
}
