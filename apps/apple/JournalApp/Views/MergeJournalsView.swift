import JournalCore
import SwiftUI

/// Merge Journals (docs/design/join-with-local-journals.md §3.2): before this device's journals go to a server, it
/// names the server and what will be merged. The toolbar's Merge button continues.
struct MergeJournalsContent: View {
    @ObservedObject var flow: ConnectionFlow
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            Text("The journals on this device will be merged with the journals on \(flow.host).")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.listRowBackground(Color.clear)
        Section {
            LabeledContent("Server", value: flow.host).textSelection(.enabled)
            LabeledContent("On This Device", value: Self.summary(model.libraryContents))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(footer, id: \.self) { Text($0).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    /// "3 journals, 42 entries, 2 templates, 3 recently deleted": journals and entries always, the rest when there
    /// are any.
    static func summary(_ contents: LibraryContents) -> String {
        var parts = [
            count(contents.journals, "journal", "journals"), count(contents.entries, "entry", "entries"),
        ]
        if contents.templates > 0 { parts.append(count(contents.templates, "template", "templates")) }
        if contents.recentlyDeleted > 0 { parts.append("\(contents.recentlyDeleted) recently deleted") }
        return parts.joined(separator: ", ")
    }
    private static func count(_ number: Int, _ one: String, _ many: String) -> String {
        "\(number) \(number == 1 ? one : many)"
    }

    private var footer: [String] {
        var lines = [
            "Journals already on the server are kept. A journal with the same name as one there is combined with it, unless you chose that journal for an agent. Then yours is added with a number, such as “Default 2”."
        ]
        if let encryption { lines.append(encryption) }
        lines.append("To leave something out, cancel and delete it first, including from Recently Deleted.")
        lines.append("Merge only if \(flow.host) is your server.")
        return lines
    }
    /// What happens to this device's encryption (§2.5). An encrypted device never reaches this step for a server
    /// without encryption.
    private var encryption: String? {
        guard let envelope = flow.envelope else { return nil }
        let serverEncrypts = [1, 2].contains(envelope.formatVersion)
        let deviceEncrypts = model.configuration?.encrypted == true
        switch (deviceEncrypts, serverEncrypts) {
        case (false, true): return "They’ll be encrypted before they’re uploaded."
        case (true, true):
            let server = flow.credentialName.lowercased()
            let device = flow.existingCredentialName.lowercased()
            return
                "Afterward, this device uses the same \(server) as your other devices. Archives you exported earlier still open with the \(device) you use now."
        case (false, false): return "They aren’t encrypted, so anyone with access to the server can read them."
        case (true, false): return nil
        }
    }
}
