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
        Capability(id: "INCREASED_MEMORY_LIMIT", name: "Increased Memory Limit", detail: "Lets the app use more RAM before iOS stops it", symbol: "memorychip", tier: .free),
        Capability(id: "EXTENDED_VIRTUAL_ADDRESSING", name: "Extended Virtual Addressing", detail: "A larger address space, used by emulators and JIT apps", symbol: "square.stack.3d.down.right", tier: .free),
        Capability(id: "NETWORK_EXTENSIONS", name: "Network Extensions", detail: "Packet tunnels, content filters and DNS proxies", symbol: "network", tier: .free),
        Capability(id: "PERSONAL_VPN", name: "Personal VPN", detail: "Create and control VPN configurations", symbol: "lock.shield", tier: .free),
        Capability(id: "ACCESS_WIFI_INFORMATION", name: "Access Wi-Fi Information", detail: "Read the current Wi-Fi network's name", symbol: "wifi", tier: .free),
        Capability(id: "HOT_SPOT", name: "Hotspot", detail: "Configure Wi-Fi networks and hotspots", symbol: "personalhotspot", tier: .free),
        Capability(id: "MULTIPATH", name: "Multipath", detail: "Use Wi-Fi and cellular at the same time", symbol: "arrow.triangle.branch", tier: .free),
        Capability(id: "NFC_TAG_READING", name: "NFC Tag Reading", detail: "Read NFC tags", symbol: "wave.3.right", tier: .free),
        Capability(id: "HEALTHKIT", name: "HealthKit", detail: "Read and write Health data", symbol: "heart", tier: .free),
        Capability(id: "HOMEKIT", name: "HomeKit", detail: "Control Home accessories", symbol: "house", tier: .free),
        Capability(id: "SIRIKIT", name: "SiriKit", detail: "Handle Siri requests", symbol: "mic", tier: .free),
        Capability(id: "WIRELESS_ACCESSORY_CONFIGURATION", name: "Wireless Accessory Configuration", detail: "Set up MFi Wi-Fi accessories", symbol: "antenna.radiowaves.left.and.right", tier: .free),
        Capability(id: "INTER_APP_AUDIO", name: "Inter-App Audio", detail: "Share audio with other apps", symbol: "waveform", tier: .free),

        // Need a paid Apple Developer Program membership.
        Capability(id: "PUSH_NOTIFICATIONS", name: "Push Notifications", detail: "Receive remote notifications", symbol: "bell.badge", tier: .paid),
        Capability(id: "ASSOCIATED_DOMAINS", name: "Associated Domains", detail: "Universal links and shared web credentials", symbol: "link", tier: .paid),
        Capability(id: "GAME_CENTER", name: "Game Center", detail: "Leaderboards, achievements and multiplayer", symbol: "gamecontroller", tier: .paid),
        Capability(id: "IN_APP_PURCHASE", name: "In-App Purchase", detail: "Sell content inside the app", symbol: "cart", tier: .paid),
        Capability(id: "SIGN_IN_WITH_APPLE", name: "Sign in with Apple", detail: "Let people sign in with their Apple Account", symbol: "apple.logo", tier: .paid),
        Capability(id: "WALLET", name: "Wallet", detail: "Add passes to Wallet", symbol: "wallet.pass", tier: .paid),
        Capability(id: "CLASSKIT", name: "ClassKit", detail: "Share progress with Schoolwork", symbol: "graduationcap", tier: .paid),
        Capability(id: "AUTOFILL_CREDENTIAL_PROVIDER", name: "AutoFill Credential Provider", detail: "Offer passwords to AutoFill", symbol: "key", tier: .paid),
        Capability(id: "FONT_INSTALLATION", name: "Fonts", detail: "Install fonts system-wide", symbol: "textformat", tier: .paid),
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

/// Settings › Entitlements: switches for capabilities AltStore is signed with.
struct EntitlementsView: View {
    @ObservedObject private var settings = EntitlementSettings.shared

    var body: some View {
        AuroraScreen {
            Text("Switched-on entitlements are enabled on AltStore's App ID with your Apple ID, then added to its signature the next time you install or refresh it.")
                .font(.footnote)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            CardSection(title: "Free Apple ID", symbol: "person.crop.circle") {
                ForEach(Capability.all.filter { $0.tier == .free }) { row($0) }
                note("Personal teams can usually enable these.")
            }

            CardSection(title: "Paid Developer Account", symbol: "star.circle", tint: Aurora.ember) {
                ForEach(Capability.all.filter { $0.tier == .paid }) { row($0) }
                note("These need an Apple Developer Program membership. On a free Apple ID, Apple refuses them and the install stops with the reason, so leave them off there.")
            }

            Button(role: .destructive) {
                settings.enabled = []
            } label: {
                Label("Turn All Off", systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(settings.enabled.isEmpty)

            note("Turning one off stops AltLoad asking for it. Apple keeps it on the App ID until you remove it at developer.apple.com, so the profile may still include it.")
                .multilineTextAlignment(.center)
        }
        .navigationTitle("Entitlements")
        .toolbarTitleDisplayMode(.inline)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Aurora.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ capability: Capability) -> some View {
        Toggle(isOn: settings.binding(capability)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.name)
                    Text(capability.detail)
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                }
            } icon: {
                Image(systemName: capability.symbol)
                    .foregroundStyle(capability.tier == .paid ? Aurora.ember : Aurora.sky)
            }
        }
    }
}

#Preview {
    NavigationStack { EntitlementsView() }
        .auroraTheme()
}
