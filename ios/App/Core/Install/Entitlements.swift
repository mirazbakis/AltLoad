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

    static let all: [Capability] = [
        // Personal (free) teams can enable these.
        Capability(id: "INCREASED_MEMORY_LIMIT", name: String(localized: "Increased Memory Limit"), detail: String(localized: "Lets the app use more RAM before iOS stops it"), symbol: "memorychip", tier: .free),
        Capability(id: "EXTENDED_VIRTUAL_ADDRESSING", name: String(localized: "Extended Virtual Addressing"), detail: String(localized: "A larger address space, used by emulators and JIT apps"), symbol: "square.stack.3d.down.right", tier: .free),
        Capability(id: "NETWORK_EXTENSIONS", name: String(localized: "Network Extensions"), detail: String(localized: "Packet tunnels, content filters and DNS proxies"), symbol: "network", tier: .free),
        Capability(id: "PERSONAL_VPN", name: String(localized: "Personal VPN"), detail: String(localized: "Create and control VPN configurations"), symbol: "lock.shield", tier: .free),
        Capability(id: "ACCESS_WIFI_INFORMATION", name: String(localized: "Access Wi-Fi Information"), detail: String(localized: "Read the current Wi-Fi network's name"), symbol: "wifi", tier: .free),
        Capability(id: "HOT_SPOT", name: String(localized: "Hotspot"), detail: String(localized: "Configure Wi-Fi networks and hotspots"), symbol: "personalhotspot", tier: .free),
        Capability(id: "MULTIPATH", name: String(localized: "Multipath"), detail: String(localized: "Use Wi-Fi and cellular at the same time"), symbol: "arrow.triangle.branch", tier: .free),
        Capability(id: "NFC_TAG_READING", name: String(localized: "NFC Tag Reading"), detail: String(localized: "Read NFC tags"), symbol: "wave.3.right", tier: .free),
        Capability(id: "HEALTHKIT", name: String(localized: "HealthKit"), detail: String(localized: "Read and write Health data"), symbol: "heart", tier: .free),
        Capability(id: "HOMEKIT", name: String(localized: "HomeKit"), detail: String(localized: "Control Home accessories"), symbol: "house", tier: .free),
        Capability(id: "SIRIKIT", name: String(localized: "SiriKit"), detail: String(localized: "Handle Siri requests"), symbol: "mic", tier: .free),
        Capability(id: "WIRELESS_ACCESSORY_CONFIGURATION", name: String(localized: "Wireless Accessory Configuration"), detail: String(localized: "Set up MFi Wi-Fi accessories"), symbol: "antenna.radiowaves.left.and.right", tier: .free),
        Capability(id: "INTER_APP_AUDIO", name: String(localized: "Inter-App Audio"), detail: String(localized: "Share audio with other apps"), symbol: "waveform", tier: .free),

        // Need a paid Apple Developer Program membership.
        Capability(id: "PUSH_NOTIFICATIONS", name: String(localized: "Push Notifications"), detail: String(localized: "Receive remote notifications"), symbol: "bell.badge", tier: .paid),
        Capability(id: "ASSOCIATED_DOMAINS", name: String(localized: "Associated Domains"), detail: String(localized: "Universal links and shared web credentials"), symbol: "link", tier: .paid),
        Capability(id: "GAME_CENTER", name: String(localized: "Game Center"), detail: String(localized: "Leaderboards, achievements and multiplayer"), symbol: "gamecontroller", tier: .paid),
        Capability(id: "IN_APP_PURCHASE", name: String(localized: "In-App Purchase"), detail: String(localized: "Sell content inside the app"), symbol: "cart", tier: .paid),
        Capability(id: "SIGN_IN_WITH_APPLE", name: String(localized: "Sign in with Apple"), detail: String(localized: "Let people sign in with their Apple Account"), symbol: "apple.logo", tier: .paid),
        Capability(id: "WALLET", name: String(localized: "Wallet"), detail: String(localized: "Add passes to Wallet"), symbol: "wallet.pass", tier: .paid),
        Capability(id: "CLASSKIT", name: String(localized: "ClassKit"), detail: String(localized: "Share progress with Schoolwork"), symbol: "graduationcap", tier: .paid),
        Capability(id: "AUTOFILL_CREDENTIAL_PROVIDER", name: String(localized: "AutoFill Credential Provider"), detail: String(localized: "Offer passwords to AutoFill"), symbol: "key", tier: .paid),
        Capability(id: "FONT_INSTALLATION", name: String(localized: "Fonts"), detail: String(localized: "Install fonts system-wide"), symbol: "textformat", tier: .paid),
    ]
}

/// Which capabilities the user switched on. Applied on every install and refresh.
@MainActor
final class EntitlementSettings: ObservableObject {
    static let shared = EntitlementSettings()

    private let key = "entitlements.enabled"

    @Published var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled).sorted(), forKey: key) }
    }

    private init() {
        enabled = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func binding(_ capability: Capability) -> Binding<Bool> {
        Binding(
            get: { self.enabled.contains(capability.id) },
            set: { on in
                if on { self.enabled.insert(capability.id) } else { self.enabled.remove(capability.id) }
            })
    }

    /// In catalogue order, as the comma-separated list the signer takes.
    var requestValue: String {
        Capability.all.filter { enabled.contains($0.id) }.map(\.id).joined(separator: ",")
    }

    var hasPaid: Bool {
        Capability.all.contains { $0.tier == .paid && enabled.contains($0.id) }
    }
}
