import SwiftUI

/// The project's pages and the App Store review page: Settings ▸ About on iPhone and iPad, and the Help menu on the
/// Mac and on iPad with a menu bar (docs/design/about-and-ratings-2026-10-05.md §1–2). The addresses are the ones the
/// App Store listing uses.
enum AboutLink: Identifiable {
    case guide, support, privacyPolicy, sourceCode, rate

    var id: Self { self }

    /// Settings ▸ About, in this order.
    static let settingsRows: [AboutLink] = [.privacyPolicy, .support, .sourceCode, .rate]

    /// The row in Settings ▸ About, under its header.
    var settingsTitle: String {
        switch self {
        case .guide: return "Help"
        case .support: return "Support"
        case .privacyPolicy: return "Privacy Policy"
        case .sourceCode: return "Source Code"
        case .rate: return "Rate My Journal"
        }
    }

    /// The Help menu item, read without a header, so it names the app.
    var menuTitle: String {
        switch self {
        case .guide: return "My Journal Help"
        case .support: return "My Journal Support"
        case .privacyPolicy: return "Privacy Policy"
        case .sourceCode: return "Source Code on GitHub"
        case .rate: return "Rate My Journal"
        }
    }

    static let repository = "https://github.com/ralphkrauss/my-journal"
    /// The sync guide, which starts with how to set up a server.
    static let syncGuide = URL(string: repository + "/blob/main/docs/guide/sync.md")
    /// The steps for a Mac and its devices that synced through the server Mac builds once ran (FormerMacServer.swift).
    static let formerMacServerGuide = URL(string: repository + "/blob/main/docs/guide/sync.md#if-you-used-use-this-mac")

    /// “My Journal can’t open your journals”, the troubleshooting guide's section for the screen of that name.
    static let cantOpenGuide = URL(
        string: repository + "/blob/main/docs/guide/troubleshooting.md#my-journal-cant-open-your-journals")

    /// Text for a footer link.
    static func link(_ title: String, to url: URL?) -> Text {
        var text = AttributedString(title)
        text[AttributeScopes.FoundationAttributes.LinkAttribute.self] = url
        return Text(text)
    }

    var url: URL? {
        let repository = Self.repository
        switch self {
        case .guide: return URL(string: repository + "/blob/main/docs/guide/README.md")
        case .support: return URL(string: repository + "/blob/main/SUPPORT.md")
        case .privacyPolicy: return URL(string: repository + "/blob/main/PRIVACY.md")
        case .sourceCode: return URL(string: repository)
        case .rate:
            // The Mac opens the App Store app itself rather than a web page that hands over to it.
            #if os(macOS)
                return URL(string: "macappstore://apps.apple.com/app/id6816758959?action=write-review")
            #else
                return URL(string: "https://apps.apple.com/app/id6816758959?action=write-review")
            #endif
        }
    }

    /// "Version 1.0 (17)", as Apple's apps show it, and how VoiceOver reads it.
    static var version: (text: String, spoken: String) {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else {
            return ("Version \(version)", "Version \(version)")
        }
        return ("Version \(version) (\(build))", "Version \(version), build \(build)")
    }
}

#if os(iOS)
    /// Settings ▸ About: links that leave the app, and the version.
    struct AboutSection: View {
        var body: some View {
            Section {
                ForEach(AboutLink.settingsRows) { link in
                    if let url = link.url { Link(link.settingsTitle, destination: url) }
                }
            } header: {
                Text("About")
            } footer: {
                let version = AboutLink.version
                Text(version.text).textSelection(.enabled).accessibilityLabel(version.spoken)
            }
        }
    }
#endif

/// The Help menu: the user guide on ⌘?, the project's pages, then the review page.
struct HelpMenuItems: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        item(.guide).keyboardShortcut("?", modifiers: .command)
        Divider()
        item(.support)
        item(.privacyPolicy)
        item(.sourceCode)
        Divider()
        item(.rate)
    }

    private func item(_ link: AboutLink) -> some View {
        Button(link.menuTitle) {
            if let url = link.url { openURL(url) }
        }
    }
}
