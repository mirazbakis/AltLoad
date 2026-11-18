import Foundation

/// A developer team on an Apple ID, as the core lists it.
struct DevTeam: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    /// Apple's team type, e.g. "Individual" or "Company/Organization".
    var type: String? = nil
    /// "free", "individual", "organization" or "unknown".
    var kind: String? = nil

    var isFree: Bool { kind == "free" }

    var displayName: String { name.isEmpty ? id : name }

    var kindTitle: String {
        switch kind {
        case "free": String(localized: "Free personal team")
        case "individual": String(localized: "Paid individual")
        case "organization": String(localized: "Organization")
        default: String(localized: "Team")
        }
    }
}

/// Which developer team AltLoad signs with, per Apple ID. Automatic (nil) uses
/// the account's first team. Sent with every install, refresh and account request.
@MainActor
final class TeamSettings: ObservableObject {
    static let shared = TeamSettings()

    private let selectionKey = "account.teamSelection"
    private let teamsKey = "account.teams"

    /// Apple ID (lowercased) → chosen team ID.
    @Published private(set) var selection: [String: String] {
        didSet { UserDefaults.standard.set(selection, forKey: selectionKey) }
    }
    /// Apple ID (lowercased) → its teams, from the last account overview.
    @Published private(set) var teams: [String: [DevTeam]] {
        didSet {
            if let data = try? JSONEncoder().encode(teams) { UserDefaults.standard.set(data, forKey: teamsKey) }
        }
    }
    /// Shown once after a chosen team was missing and Automatic took over.
    @Published var fallbackNote: String?

    private init() {
        selection = UserDefaults.standard.dictionary(forKey: selectionKey) as? [String: String] ?? [:]
        teams = (UserDefaults.standard.data(forKey: teamsKey))
            .flatMap { try? JSONDecoder().decode([String: [DevTeam]].self, from: $0) } ?? [:]
    }

    private func key(_ appleID: String) -> String { appleID.lowercased() }

    /// The chosen team ID for this Apple ID, or nil for Automatic.
    func teamID(for appleID: String) -> String? {
        selection[key(appleID)]
    }

    func teams(for appleID: String) -> [DevTeam] {
        teams[key(appleID)] ?? []
    }

    func select(_ teamID: String?, for appleID: String) {
        guard !appleID.isEmpty else { return }
        selection[key(appleID)] = teamID
        let name = teamID.flatMap { id in teams(for: appleID).first { $0.id == id }?.displayName } ?? "Automatic"
        AppLog.shared.info(.account, "Developer team set to \(name) for \(appleID)")
    }

    /// The team AltLoad will sign with for this Apple ID, if its teams are known.
    func effectiveTeam(for appleID: String) -> DevTeam? {
        let list = teams(for: appleID)
        if let id = teamID(for: appleID), let team = list.first(where: { $0.id == id }) { return team }
        return list.first
    }

    /// True when the team AltLoad will use is known to be a free personal team.
    func isFreeTeam(for appleID: String) -> Bool {
        effectiveTeam(for: appleID)?.isFree ?? false
    }

    /// Saves the teams from an account overview, and drops a choice that's gone.
    func update(teams list: [DevTeam], for appleID: String, note: String?) {
        guard !appleID.isEmpty, !list.isEmpty else { return }
        teams[key(appleID)] = list
        if let id = teamID(for: appleID), !list.contains(where: { $0.id == id }) {
            fallBack(for: appleID, note: note)
        }
    }

    /// The core used the first team because the chosen one is gone.
    func fallBack(for appleID: String, note: String?) {
        guard teamID(for: appleID) != nil else { return }
        selection[key(appleID)] = nil
        let message = note ?? String(localized: "The developer team you picked isn't on this Apple ID anymore.")
        fallbackNote = message + " " + String(localized: "AltLoad switched back to Automatic.")
        AppLog.shared.error(.account, "Chosen team missing, back to Automatic: \(message)")
    }
}
