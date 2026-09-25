import Foundation

/// Finds `_remotepairing._tcp` services on the local network: this iPhone's own
/// RemotePairing endpoint plus any others. The Rust side matches them to the
/// pairing file by their `authTag` and only tunnels to the one that verifies.
@MainActor
final class SelfDiscovery: NSObject {
    struct Endpoint: Hashable {
        let host: String
        let port: Int
        let identifier: String
        let authTag: String
    }

    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]
    private var found: [String: Endpoint] = [:]

    override init() {
        super.init()
        browser.delegate = self
    }

    /// Browses for `timeout` seconds and returns everything resolved so far.
    func discover(timeout: TimeInterval = 4) async -> [Endpoint] {
        services.removeAll()
        found.removeAll()
        browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
        try? await Task.sleep(for: .seconds(timeout))
        browser.stop()
        for service in services.values { service.stop() }
        return Array(found.values)
    }

    private func key(_ service: NetService) -> String {
        "\(service.name).\(service.type)\(service.domain)"
    }

    private func update(_ service: NetService) {
        guard let host = service.hostName, service.port > 0 else { return }
        let txt = service.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        func value(_ k: String) -> String {
            txt[k].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        found[key(service)] = Endpoint(
            host: host,
            port: service.port,
            identifier: value("identifier").isEmpty ? service.name : value("identifier"),
            authTag: value("authTag"))
    }
}

extension SelfDiscovery: NetServiceBrowserDelegate {
    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        Task { @MainActor in
            services[key(service)] = service
            service.delegate = self
            service.resolve(withTimeout: 4)
        }
    }
}

extension SelfDiscovery: NetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        Task { @MainActor in update(sender) }
    }

    nonisolated func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        Task { @MainActor in update(sender) }
    }
}
