import SwiftUI

enum ToolRoute: Hashable {
    case altServer, pair, pairingToApps, library, certificates
}

/// Lets other screens open a tool (e.g. "Go to Pair" from Install).
@MainActor
final class ToolsRouter: ObservableObject {
    static let shared = ToolsRouter()
    @Published var path: [ToolRoute] = []
    private init() {}
}

/// One tab for everything that isn't installing: AltServer, pairing, pairing
/// files for other apps, the library and the Apple ID's certificates.
struct ToolsView: View {
    @ObservedObject private var router = ToolsRouter.shared
    @ObservedObject private var altServer = AltServerHost.shared
    @ObservedObject private var pairings = PairingStore.shared
    @ObservedObject private var install = InstallController.shared

    var body: some View {
        NavigationStack(path: $router.path) {
            AuroraScreen {
                VStack(spacing: 10) {
                    SectionLabel(title: "AltStore")
                    toolRow(.altServer, symbol: "server.rack", title: "AltServer",
                            detail: altServerDetail,
                            tint: altServer.isRunning ? Aurora.success : Aurora.violet)
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Pairing")
                    toolRow(.pair, symbol: "antenna.radiowaves.left.and.right", title: "Pair",
                            detail: pairings.selfPairing.map { "This iPhone: \($0.displayName)" } ?? "Create this iPhone's pairing file")
                    toolRow(.pairingToApps, symbol: "doc.badge.gearshape", title: "Pairing File to Apps",
                            detail: "Put the pairing file inside Catalyst, SideStore, StikDebug and others")
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Apps & Account")
                    toolRow(.library, symbol: "tray.full.fill", title: "Library",
                            detail: libraryDetail)
                    toolRow(.certificates, symbol: "checkmark.seal.fill", title: "Certificates",
                            detail: "Your Apple ID's certificates, App IDs and devices")
                }
            }
            .navigationTitle("Tools")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: ToolRoute.self) { route in
                switch route {
                case .altServer: AltServerView()
                case .pair: PairView()
                case .pairingToApps: PairingToAppsView()
                case .library: LibraryView()
                case .certificates: CertificatesView()
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

    private var libraryDetail: String {
        let n = install.apps.count
        let files = pairings.items.count
        return "\(n) app\(n == 1 ? "" : "s") · \(files) pairing file\(files == 1 ? "" : "s")"
    }

    private func toolRow(_ route: ToolRoute, symbol: String, title: String, detail: String, tint: Color = Aurora.violet) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Aurora.frost)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(tint.opacity(0.5)), in: .circle)
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Aurora.card.opacity(0.6)).interactive(), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Aurora.hairline, lineWidth: 1)
        }
    }
}
