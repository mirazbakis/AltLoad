import SwiftUI

@main
struct AltLoadApp: App {
    init() {
        PairingController.shared.registerBackgroundTask()
        // Be ready as soon as AltStore looks for an AltServer.
        AltServerHost.shared.startIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .auroraTheme()
        }
    }
}

enum AppTab: Hashable {
    case install, tools, settings
}

struct RootView: View {
    @State private var tab: AppTab = .install
    @StateObject private var install = InstallController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            Tab("Install", systemImage: "arrow.down.app.fill", value: AppTab.install) {
                InstallView(selectedTab: $tab)
            }
            Tab("Tools", systemImage: "wrench.and.screwdriver.fill", value: AppTab.tools) {
                ToolsView()
            }
            .badge(expiringSoon)
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Installs and refreshes run full screen over whichever tab started them.
        .fullScreenCover(item: $install.flow) { target in
            InstallFlowView(target: target) { RootView.openPair(tab: $tab) }
                .auroraTheme()
        }
        .onOpenURL { url in
            // LocalDevVPN returns here via altload:// after switching the VPN on.
            guard url.scheme == "altload" else { return }
            install.resumeWhenVPNReady()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AltServerHost.shared.refresh() }
        }
    }

    /// Apps that expire within a day (or already have), shown on the Tools tab.
    private var expiringSoon: Int {
        install.apps.filter { $0.isExpired || ($0.daysLeft ?? 99) < 1 }.count
    }

    /// Switches to Tools and opens Pair.
    static func openPair(tab: Binding<AppTab>) {
        tab.wrappedValue = .tools
        ToolsRouter.shared.path = [.pair]
    }
}
