import SwiftUI

/// A capability AltLoad can switch on for AltStore's App ID before signing. Apple
/// then puts its entitlement in the provisioning profile, and the signature carries it.
struct Capability: Identifiable, Hashable {
    enum Tier { case free, paid }

    /// App Store Connect capability ID, sent as-is to Apple.
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let tier: Tier
    /// The entitlement Apple puts in the profile for it, when there is one.
    var entitlement: String? = nil

    static let all: [Capability] = [
        // Personal (free) teams can enable these.
        Capability(id: "INCREASED_MEMORY_LIMIT", name: String(localized: "Increased Memory Limit"), detail: String(localized: "Lets the app use more RAM before iOS stops it"), symbol: "memorychip", tier: .free, entitlement: "com.apple.developer.kernel.increased-memory-limit"),
        Capability(id: "EXTENDED_VIRTUAL_ADDRESSING", name: String(localized: "Extended Virtual Addressing"), detail: String(localized: "A larger address space, used by emulators and JIT apps"), symbol: "square.stack.3d.down.right", tier: .free, entitlement: "com.apple.developer.kernel.extended-virtual-addressing"),
        Capability(id: "NETWORK_EXTENSIONS", name: String(localized: "Network Extensions"), detail: String(localized: "Packet tunnels, content filters and DNS proxies"), symbol: "network", tier: .free, entitlement: "com.apple.developer.networking.networkextension"),
        Capability(id: "PERSONAL_VPN", name: String(localized: "Personal VPN"), detail: String(localized: "Create and control VPN configurations"), symbol: "lock.shield", tier: .free, entitlement: "com.apple.developer.networking.vpn.api"),
        Capability(id: "ACCESS_WIFI_INFORMATION", name: String(localized: "Access Wi-Fi Information"), detail: String(localized: "Read the current Wi-Fi network's name"), symbol: "wifi", tier: .free, entitlement: "com.apple.developer.networking.wifi-info"),
        Capability(id: "HOT_SPOT", name: String(localized: "Hotspot"), detail: String(localized: "Configure Wi-Fi networks and hotspots"), symbol: "personalhotspot", tier: .free, entitlement: "com.apple.developer.networking.HotspotConfiguration"),
        Capability(id: "MULTIPATH", name: String(localized: "Multipath"), detail: String(localized: "Use Wi-Fi and cellular at the same time"), symbol: "arrow.triangle.branch", tier: .free, entitlement: "com.apple.developer.networking.multipath"),
        Capability(id: "NFC_TAG_READING", name: String(localized: "NFC Tag Reading"), detail: String(localized: "Read NFC tags"), symbol: "wave.3.right", tier: .free, entitlement: "com.apple.developer.nfc.readersession.formats"),
        Capability(id: "HEALTHKIT", name: String(localized: "HealthKit"), detail: String(localized: "Read and write Health data"), symbol: "heart", tier: .free, entitlement: "com.apple.developer.healthkit"),
        Capability(id: "HOMEKIT", name: String(localized: "HomeKit"), detail: String(localized: "Control Home accessories"), symbol: "house", tier: .free, entitlement: "com.apple.developer.homekit"),
        Capability(id: "SIRIKIT", name: String(localized: "SiriKit"), detail: String(localized: "Handle Siri requests"), symbol: "mic", tier: .free, entitlement: "com.apple.developer.siri"),
        Capability(id: "WIRELESS_ACCESSORY_CONFIGURATION", name: String(localized: "Wireless Accessory Configuration"), detail: String(localized: "Set up MFi Wi-Fi accessories"), symbol: "antenna.radiowaves.left.and.right", tier: .free, entitlement: "com.apple.external-accessory.wireless-configuration"),
        Capability(id: "INTER_APP_AUDIO", name: String(localized: "Inter-App Audio"), detail: String(localized: "Share audio with other apps"), symbol: "waveform", tier: .free, entitlement: "inter-app-audio"),

        // Need a paid Apple Developer Program membership.
        Capability(id: "PUSH_NOTIFICATIONS", name: String(localized: "Push Notifications"), detail: String(localized: "Receive remote notifications"), symbol: "bell.badge", tier: .paid, entitlement: "aps-environment"),
        Capability(id: "ASSOCIATED_DOMAINS", name: String(localized: "Associated Domains"), detail: String(localized: "Universal links and shared web credentials"), symbol: "link", tier: .paid, entitlement: "com.apple.developer.associated-domains"),
        Capability(id: "GAME_CENTER", name: String(localized: "Game Center"), detail: String(localized: "Leaderboards, achievements and multiplayer"), symbol: "gamecontroller", tier: .paid, entitlement: "com.apple.developer.game-center"),
        Capability(id: "IN_APP_PURCHASE", name: String(localized: "In-App Purchase"), detail: String(localized: "Sell content inside the app"), symbol: "cart", tier: .paid),
        Capability(id: "SIGN_IN_WITH_APPLE", name: String(localized: "Sign in with Apple"), detail: String(localized: "Let people sign in with their Apple Account"), symbol: "apple.logo", tier: .paid, entitlement: "com.apple.developer.applesignin"),
        Capability(id: "WALLET", name: String(localized: "Wallet"), detail: String(localized: "Add passes to Wallet"), symbol: "wallet.pass", tier: .paid, entitlement: "com.apple.developer.pass-type-identifiers"),
        Capability(id: "CLASSKIT", name: String(localized: "ClassKit"), detail: String(localized: "Share progress with Schoolwork"), symbol: "graduationcap", tier: .paid, entitlement: "com.apple.developer.ClassKit-environment"),
        Capability(id: "AUTOFILL_CREDENTIAL_PROVIDER", name: String(localized: "AutoFill Credential Provider"), detail: String(localized: "Offer passwords to AutoFill"), symbol: "key", tier: .paid, entitlement: "com.apple.developer.authentication-services.autofill-credential-provider"),
        Capability(id: "FONT_INSTALLATION", name: String(localized: "Fonts"), detail: String(localized: "Install fonts system-wide"), symbol: "textformat", tier: .paid, entitlement: "com.apple.developer.user-fonts"),
    ]
}

/// A ready-made set of capabilities.
struct CapabilityPreset: Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let capabilities: [String]

    static let all: [CapabilityPreset] = [
        CapabilityPreset(id: "emulators", name: String(localized: "Emulators & JIT apps"),
                         detail: String(localized: "Increased Memory Limit and Extended Virtual Addressing"),
                         symbol: "gamecontroller",
                         capabilities: ["INCREASED_MEMORY_LIMIT", "EXTENDED_VIRTUAL_ADDRESSING"]),
        CapabilityPreset(id: "network", name: String(localized: "VPN & network tools"),
                         detail: String(localized: "Network Extensions, Personal VPN, Wi-Fi Information and Multipath"),
                         symbol: "network",
                         capabilities: ["NETWORK_EXTENSIONS", "PERSONAL_VPN", "ACCESS_WIFI_INFORMATION", "MULTIPATH"]),
    ]
}

/// Which capabilities the user switched on: one set for every app, and an own
/// set for any installed app that has one. Applied on every install and refresh.
@MainActor
final class EntitlementSettings: ObservableObject {
    static let shared = EntitlementSettings()

    private let key = "entitlements.enabled"
    private let overridesKey = "entitlements.overrides"

    /// The set every app uses unless it has its own.
    @Published var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled).sorted(), forKey: key) }
    }

    /// Installed bundle ID → that app's own set.
    @Published private(set) var overrides: [String: Set<String>] {
        didSet {
            UserDefaults.standard.set(overrides.mapValues { Array($0).sorted() }, forKey: overridesKey)
        }
    }

    private init() {
        enabled = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        let saved = UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: [String]] ?? [:]
        overrides = saved.mapValues(Set.init)
    }

    // MARK: - Editing

    /// nil edits the shared set.
    func set(for bundleID: String?) -> Set<String> {
        guard let bundleID, let own = overrides[bundleID] else { return enabled }
        return own
    }

    func hasOwnSet(_ bundleID: String) -> Bool { overrides[bundleID] != nil }

    /// Starts an app's own set from the shared one, or drops it.
    func setUsesOwn(_ own: Bool, for bundleID: String) {
        overrides[bundleID] = own ? enabled : nil
    }

    func binding(_ capability: Capability, for bundleID: String? = nil) -> Binding<Bool> {
        Binding(
            get: { self.set(for: bundleID).contains(capability.id) },
            set: { on in
                self.update(for: bundleID) { set in
                    if on { set.insert(capability.id) } else { set.remove(capability.id) }
                }
            })
    }

    func apply(_ preset: CapabilityPreset, for bundleID: String? = nil) {
        update(for: bundleID) { $0.formUnion(preset.capabilities) }
    }

    func clear(for bundleID: String? = nil) {
        update(for: bundleID) { $0.removeAll() }
    }

    private func update(for bundleID: String?, _ change: (inout Set<String>) -> Void) {
        if let bundleID, var own = overrides[bundleID] {
            change(&own)
            overrides[bundleID] = own
        } else {
            change(&enabled)
        }
    }

    // MARK: - Requests

    /// The comma-separated list the signer takes, in catalogue order. Paid-only
    /// capabilities are left out when the team is known to be a free personal
    /// team, since Apple refuses them and the install would stop.
    func requestValue(for bundleID: String?, freeTeam: Bool) -> String {
        let chosen = set(for: bundleID)
        return Capability.all
            .filter { chosen.contains($0.id) && !(freeTeam && $0.tier == .paid) }
            .map(\.id)
            .joined(separator: ",")
    }

    /// The shared set's list, for callers without an app.
    var requestValue: String { requestValue(for: nil, freeTeam: false) }

    func hasPaid(for bundleID: String? = nil) -> Bool {
        let chosen = set(for: bundleID)
        return Capability.all.contains { $0.tier == .paid && chosen.contains($0.id) }
    }

    var hasPaid: Bool { hasPaid(for: nil) }

    /// Forgets sets for apps AltLoad no longer lists.
    func prune(keeping bundleIDs: Set<String>) {
        let stale = overrides.keys.filter { !bundleIDs.contains($0) }
        guard !stale.isEmpty else { return }
        for id in stale { overrides[id] = nil }
    }
}
