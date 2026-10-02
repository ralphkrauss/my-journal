import Foundation
import JournalCore
import Network

/// A server another device announced on the local network with Bonjour. Only a suggestion: the address is checked
/// exactly as a typed one, and it stays visible while connecting.
struct DiscoveredServer: Identifiable, Equatable {
    /// The HTTPS address from the announcement's `url` value.
    let address: String
    /// The announced name, for example “My Journal on server”.
    let name: String
    var id: String { address }
    /// The part of the address the server's certificate proves, shown first.
    var host: String { ServerAddress.host(address) }
}

/// Looks for `_myjournal._tcp` servers while Connect to a Server is choosing one.
@MainActor
final class ServerBrowser: ObservableObject {
    enum State: Equatable { case idle, searching, denied }
    static let serviceType = "_myjournal._tcp"
    @Published private(set) var servers: [DiscoveredServer] = []
    @Published private(set) var state = State.idle
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())
        browser.stateUpdateHandler = { [weak self] update in
            let denied: Bool
            if case .waiting(let error) = update, case .dns(let code) = error,
                code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied)
            {
                denied = true
            } else {
                denied = false
            }
            Task { @MainActor [weak self] in
                guard let self, self.browser === browser else { return }
                self.state = denied ? .denied : .searching
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = Self.servers(in: results)
            Task { @MainActor [weak self] in
                guard let self, self.browser === browser else { return }
                self.servers = found
            }
        }
        self.browser = browser
        state = .searching
        browser.start(queue: .main)
    }

    func stop() {
        browser?.cancel()
        browser = nil
        state = .idle
    }

    /// One row per address (a server is announced on several interfaces), HTTPS only, sorted by host.
    nonisolated static func servers(in results: Set<NWBrowser.Result>) -> [DiscoveredServer] {
        var byAddress: [String: DiscoveredServer] = [:]
        for result in results {
            guard case .bonjour(let record) = result.metadata, record["v"] == "1", let address = record["url"],
                PairingInvite.origin(of: address)?.hasPrefix("https://") == true
            else { continue }
            var name = ""
            if case .service(let service, _, _, _) = result.endpoint { name = service }
            byAddress[address] = DiscoveredServer(address: address, name: name)
        }
        return byAddress.values.sorted { $0.host.localizedStandardCompare($1.host) == .orderedAscending }
    }
}

/// How an address is shown: its host, with the port when it isn't the default, so two servers on one machine differ.
enum ServerAddress {
    static func host(_ address: String) -> String {
        guard let components = URLComponents(string: address), let host = components.host else { return address }
        let defaultPort = components.scheme == "http" ? 80 : 443
        return host + (components.port.map { $0 == defaultPort ? "" : ":\($0)" } ?? "")
    }
}
