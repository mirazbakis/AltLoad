import AltLoadFFI
import Foundation
import Network

/// Where remotepairingd listens on this iPhone. iOS gives it a free port when the
/// service starts, usually 49152 but not always (after a restart it can move), and
/// advertises it over Bonjour as `_remotepairing._tcp`. AltLoad reaches it through
/// LocalDevVPN, so the host stays the VPN target and only the port is looked up.
enum RemotePairingPort {
    /// Tried after the Bonjour results. If none of them is the pairing service, the
    /// core knocks on the iPhone's other ports to find it.
    static let usualPorts = [49152]
    private static let lastKey = "vpn.remotePairingPort"

    /// The last port Bonjour reported, tried first when Bonjour finds nothing.
    static var lastKnown: Int? {
        get { (UserDefaults.standard.object(forKey: lastKey) as? Int).flatMap { $0 > 0 ? $0 : nil } }
        set { UserDefaults.standard.set(newValue, forKey: lastKey) }
    }

    /// Endpoints for the core, best first. The core tries each in turn and skips
    /// advertisements whose auth tag doesn't match the pairing file.
    @MainActor
    static func endpoints(host: String = LocalDevVPN.targetIP) async -> [SelfEndpoint] {
        let found = await RemotePairingBrowser().run(timeout: 2.5)
        var result: [SelfEndpoint] = []
        var seen = Set<Int>()
        func add(_ port: Int, identifier: String? = nil, authTag: String? = nil) {
            guard port > 0, port != Int(AltServerHost.wiredPort), seen.insert(port).inserted else { return }
            result.append(SelfEndpoint(host: host, port: port, identifier: identifier, authTag: authTag))
        }
        for service in found {
            add(service.port, identifier: service.identifier, authTag: service.authTag)
        }
        if let first = found.first { lastKnown = first.port }
        if let lastKnown { add(lastKnown) }
        usualPorts.forEach { add($0) }

        let ports = found.map { String($0.port) }.joined(separator: ", ")
        AppLog.shared.info(.vpn, found.isEmpty
            ? "Bonjour found no remote pairing service; trying the usual ports"
            : "Remote pairing advertised on port \(ports)")
        return result
    }
}

/// One `_remotepairing._tcp` advertisement.
struct RemotePairingService: Sendable {
    let port: Int
    let identifier: String?
    let authTag: String?
}

/// Browses for `_remotepairing._tcp` and resolves each result's port and TXT record.
/// The iPhone sees its own advertisement, and any other devices' on the same Wi-Fi.
@MainActor
private final class RemotePairingBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []
    private var found: [RemotePairingService] = []
    private var continuation: CheckedContinuation<[RemotePairingService], Never>?

    func run(timeout: TimeInterval) async -> [RemotePairingService] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            browser.delegate = self
            browser.searchForServices(ofType: "_remotepairing._tcp.", inDomain: "local.")
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish()
            }
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        browser.stop()
        pending.forEach { $0.stop() }
        pending.removeAll()
        continuation.resume(returning: found)
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        MainActor.assumeIsolated {
            pending.append(service)
            service.delegate = self
            service.resolve(withTimeout: 2)
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        MainActor.assumeIsolated {
            guard sender.port > 0, !found.contains(where: { $0.port == sender.port }) else { return }
            var identifier: String?
            var authTag: String?
            if let data = sender.txtRecordData() {
                let txt = NetService.dictionary(fromTXTRecord: data)
                identifier = txt["identifier"].flatMap { String(data: $0, encoding: .utf8) }
                authTag = txt["authTag"].flatMap { String(data: $0, encoding: .utf8) }
            }
            found.append(RemotePairingService(port: sender.port, identifier: identifier, authTag: authTag))
        }
    }
}

extension Array where Element == SelfEndpoint {
    /// The endpoints as a C array for the core. `c` copies a string and keeps it
    /// alive until the caller frees it; free the returned buffer with `deallocate()`.
    func cArray(_ c: (String) -> UnsafePointer<CChar>?) -> UnsafeMutablePointer<AltLoadEndpoint> {
        let buffer = UnsafeMutablePointer<AltLoadEndpoint>.allocate(capacity: Swift.max(count, 1))
        for (i, e) in enumerated() {
            buffer[i] = AltLoadEndpoint(
                host: c(e.host),
                port: UInt16(clamping: e.port),
                identifier: e.identifier.flatMap { c($0) },
                auth_tag: e.authTag.flatMap { c($0) })
        }
        return buffer
    }
}
