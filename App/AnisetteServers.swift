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

    /// Used when the live list can't be fetched. SideStore's servers first.
    static let builtIn: [AnisetteServer] = [
        AnisetteServer(name: "SideStore", address: "https://ani.sidestore.io"),
        AnisetteServer(name: "SideStore (.app)", address: "https://ani.sidestore.app"),
        AnisetteServer(name: "SideStore (.zip)", address: "https://ani.sidestore.zip"),
        AnisetteServer(name: "SideStore (.xyz)", address: "https://ani.846969.xyz"),
        AnisetteServer(name: "StikStore", address: "https://ani.stikstore.app"),
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
        servers.first { $0.address == address }?.name
    }
}
