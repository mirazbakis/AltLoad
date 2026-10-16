import SwiftUI

enum ToolRoute: Hashable {
    case altServer, pair, pairingToApps, entitlements, certificates, jit, location
}

/// Lets other screens open a tool (e.g. "Go to Pair" from Install).
@MainActor
final class ToolsRouter: ObservableObject {
    static let shared = ToolsRouter()
    @Published var path: [ToolRoute] = []
    private init() {}
}

/// One tab for everything that isn't installing: AltServer, JIT, location,
/// pairing, pairing files for other apps, entitlements and the Apple ID's certificates.
struct ToolsView: View {
    @ObservedObject private var router = ToolsRouter.shared
    @ObservedObject private var altServer = AltServerHost.shared
    @ObservedObject private var pairings = PairingStore.shared
    @ObservedObject private var entitlements = EntitlementSettings.shared
    @ObservedObject private var location = LocationSpoofer.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            AuroraScreen {
                VStack(spacing: 10) {
                    SectionLabel(title: "Stores")
                    toolRow(.altServer, symbol: "server.rack", title: "AltServer",
                            detail: altServerDetail,
                            tint: altServer.isRunning ? Aurora.success : Aurora.accent)
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Developer")
                    toolRow(.jit, symbol: "bolt.fill", title: "JIT",
                            detail: "Open an emulator or other JIT app with JIT enabled")
                    toolRow(.location, symbol: "location.fill", title: "Location",
                            detail: locationDetail,
                            tint: location.isRunning ? Aurora.success : Aurora.accent)
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Pairing")
                    toolRow(.pair, symbol: "antenna.radiowaves.left.and.right", title: "Pair",
                            detail: pairings.selfPairing.map { "This iPhone: \($0.displayName)" } ?? "Create this iPhone's pairing file")
                    toolRow(.pairingToApps, symbol: "doc.badge.gearshape", title: "Pairing File to Apps",
                            detail: "Put the pairing file inside SideStore, StikDebug and others")
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Signing & Account")
                    toolRow(.entitlements, symbol: "checkmark.shield.fill", title: "Entitlements",
                            detail: entitlements.enabled.isEmpty ? "Extra capabilities for apps AltLoad signs"
                                : "\(entitlements.enabled.count) on · added on the next install or refresh")
                    toolRow(.certificates, symbol: "checkmark.seal.fill", title: "Certificates",
                            detail: "Your Apple ID's certificates, App IDs and devices")
                }
            }
            .navigationTitle("Tools")
            .toolbarTitleDisplayMode(.inlineLarge)
            .settingsButton()
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .altServer: AltServerView()
                case .pair: PairView()
                case .pairingToApps: PairingToAppsView()
                case .entitlements: EntitlementsView()
                case .certificates: CertificatesView()
                case .jit: JITView()
                case .location: LocationView()
                }
            }
        }
    }

    private var altServerDetail: String {
        guard altServer.isRunning else { return "Off. AltStore will say \"AltServer not found\"" }
        if let date = altServer.lastContact {
            return "Running · AltStore connected \(date.formatted(.relative(presentation: .named)))"
        }
        return "Running · AltStore can find it on this iPhone"
    }

    private var locationDetail: String {
        if case .active(let c) = location.state {
            return String(format: "Simulating %.4f, %.4f", c.latitude, c.longitude)
        }
        return "Make this iPhone report another location"
    }

    private func toolRow(_ route: ToolRoute, symbol: String, title: String, detail: String, tint: Color = Aurora.accent) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, tint: tint == Aurora.accent ? Aurora.accentDeep : tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Aurora.frost)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Aurora.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(14)
            .frame(minHeight: 72)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .cardSurface()
    }
}
