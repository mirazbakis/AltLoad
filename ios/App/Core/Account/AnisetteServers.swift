import Foundation

/// Public anisette v3 servers. AltLoad ships a built-in list and refreshes it
/// from SideStore's community list (https://servers.sidestore.io/servers.json).
struct AnisetteServer: Codable, Hashable, Identifiable {
    let name: String
    let address: String
    var id: String { address }
}

@MainActor
final class AnisetteServers: ObservableObject {
    static let shared = AnisetteServers()

    static let listURL = URL(string: "https://servers.sidestore.io/servers.json")!

    /// Stored as the anisette choice when AltLoad should pick a working server itself.
    static let automatic = "auto"

    /// Used when the live list can't be fetched. Since Apple started refusing most
    /// remote anisette on 12 October 2026, the Windows-ADI servers are the ones that
    /// still sign in, so they come first. jkcoxson's macOS-ADI server is next: when it's
    /// down, Automatic's health check skips it and the PC sign-in carries on as before.
    static let builtIn: [AnisetteServer] = [
        AnisetteServer(name: "jkcoxson (Windows ADI)", address: "https://ani.jkcoxson.com"),
        AnisetteServer(name: "jkcoxson (Mac ADI)", address: "https://mac-ani.jkcoxson.com"),
        AnisetteServer(name: "SideStore (Windows ADI)", address: "https://win.ani.sidestore.io"),
        AnisetteServer(name: "SideStore", address: "https://ani.sidestore.io"),
        AnisetteServer(name: "SideStore (.app)", address: "https://ani.sidestore.app"),
        AnisetteServer(name: "SideStore (.zip)", address: "https://ani.sidestore.zip"),
        AnisetteServer(name: "SideStore (.xyz)", address: "https://ani.846969.xyz"),
        AnisetteServer(name: "nythepegasus", address: "https://ani.npeg.us"),
        AnisetteServer(name: "WE. Studio", address: "https://anisette.wedotstud.io"),
        AnisetteServer(name: "crystall1nedev", address: "https://anisette.crystall1ne.dev")
    ]

    @Published private(set) var servers: [AnisetteServer] = AnisetteServers.builtIn
    @Published private(set) var isLoading = false

    private struct Listing: Decodable {
        let servers: [AnisetteServer]
    }

    /// Merges the live list into the built-in one. HTTPS only, since sign-in headers pass through it.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.listURL)
            let live = try JSONDecoder().decode(Listing.self, from: data).servers
                .filter { $0.address.lowercased().hasPrefix("https://") }
            var merged = Self.builtIn
            for server in live where !merged.contains(where: { $0.address == server.address }) {
                merged.append(server)
            }
            servers = merged
        } catch {
            servers = Self.builtIn
        }
    }

    func name(for address: String) -> String? {
        if address == Self.automatic { return "Automatic" }
        return servers.first { $0.address == address }?.name
    }

    /// The servers to sign in with, best first, joined by newlines for the Rust side,
    /// which moves on to the next one when Apple or a server rejects the anisette data.
    /// A server the user picked goes first; servers that don't answer are dropped.
    func signInList(preferred: String) async -> String {
        var order = servers.map(\.address)
        let pinned = preferred != Self.automatic && !preferred.isEmpty
        if pinned {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }
        let candidates = Array(order.prefix(8))
        let alive = await withTaskGroup(of: (String, Bool).self) { group in
            for address in candidates {
                group.addTask { (address, await Self.isAlive(address)) }
            }
            var results: [String: Bool] = [:]
            for await (address, ok) in group { results[address] = ok }
            return results
        }
        var picked = candidates.filter { alive[$0] == true }
        // A server the user chose is always tried, even if the check missed it.
        if pinned, !picked.contains(preferred) { picked.insert(preferred, at: 0) }
        if picked.isEmpty { picked = Array(candidates.prefix(3)) }
        return picked.prefix(4).joined(separator: "\n")
    }

    /// Quick check that a v3 server answers with its client info.
    nonisolated static func isAlive(_ address: String) async -> Bool {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces) + "/v3/client_info") else { return false }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["client_info"] is String
    }

    /// Removes the anisette identities AltLoad provisioned, so the next sign-in
    /// starts clean. Useful after Apple rejects one.
    nonisolated static func resetProvisioning() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AltLoad/anisette", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }
}
