import SwiftUI

@main
struct AltLoadApp: App {
    init() {
        PairingController.shared.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .auroraTheme()
        }
    }
}

enum AppTab: Hashable {
    case install, pair, certificates, library, settings
}

struct RootView: View {
    @State private var tab: AppTab = .install
    @StateObject private var store = PairingStore.shared

    var body: some View {
        TabView(selection: $tab) {
            Tab("Install", systemImage: "arrow.down.app.fill", value: AppTab.install) {
                InstallView(selectedTab: $tab)
            }
            Tab("Pair", systemImage: "antenna.radiowaves.left.and.right", value: AppTab.pair) {
                PairView()
            }
            Tab("Certificates", systemImage: "checkmark.seal.fill", value: AppTab.certificates) {
                CertificatesView()
            }
            Tab("Library", systemImage: "tray.full.fill", value: AppTab.library) {
                LibraryView()
            }
            .badge(store.items.count)
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in
            // LocalDevVPN returns here via altload:// after switching the VPN on.
            guard url.scheme == "altload" else { return }
            tab = .install
            InstallController.shared.resumeWhenVPNReady()
        }
    }
}
