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
    case install, tools, about
}

struct RootView: View {
    @State private var tab: AppTab = .install
    @StateObject private var install = InstallController.shared
    @StateObject private var updates = UpdateChecker.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $tab) {
            Tab(String(localized: "Install"), systemImage: "tray.and.arrow.down.fill", value: AppTab.install) {
                InstallView(selectedTab: $tab)
            }
            Tab(String(localized: "Tools"), systemImage: "wrench.and.screwdriver.fill", value: AppTab.tools) {
                ToolsView()
            }
            .badge(expiringSoon)
            Tab(String(localized: "About"), systemImage: "info", value: AppTab.about) {
                AboutView()
            }
        }
        .minimizingTabBarOnScroll()
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
            if phase == .active {
                AltServerHost.shared.refresh()
                Task { await updates.check() }
            }
        }
        .task { await updates.check() }
        // Waits until an install isn't covering the screen.
        .alert("Update available", isPresented: Binding(
            get: { updates.available != nil && install.flow == nil },
            set: { _ in }
        )) {
            Button("Get Update") {
                updates.dismiss()
                openURL(UpdateChecker.downloadPage)
            }
            Button("Later", role: .cancel) { updates.dismiss() }
        } message: {
            Text("AltLoad \(updates.available ?? "") is available. You have \(updates.currentVersion).")
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

private extension View {
    /// Tucks the tab bar away while scrolling down, on iOS 26 and later.
    @ViewBuilder
    func minimizingTabBarOnScroll() -> some View {
        if #available(iOS 26, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
