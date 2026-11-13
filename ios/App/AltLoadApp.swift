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
    @StateObject private var jit = JITCenter.shared
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
            guard url.scheme == "altload" else { return }
            // altload://enable-jit asks for a JIT session; AltLoad confirms first.
            if jit.handle(url: url) { return }
            // LocalDevVPN returns here via altload:// after switching the VPN on.
            install.resumeWhenVPNReady()
        }
        // Each alert sits on its own view so they don't replace one another.
        .background {
            Color.clear
                .alert(String(localized: "Enable JIT?"), isPresented: Binding(
                    get: { jit.linkRequest != nil && install.flow == nil },
                    set: { if !$0 { jit.linkRequest = nil } }
                ), presenting: jit.linkRequest) { request in
                    Button(request.scriptSource == nil ? String(localized: "Enable JIT") : String(localized: "Enable and Run Script")) {
                        jit.allow(request)
                    }
                    Button(String(localized: "Cancel"), role: .cancel) { jit.linkRequest = nil }
                } message: { request in
                    if request.scriptSource != nil {
                        Text("A link asks AltLoad to open \(request.target) with JIT and run a script it carries in AltLoad's debugger. Only allow this from apps you trust.")
                    } else {
                        Text("A link asks AltLoad to open \(request.target) with JIT.")
                    }
                }
        }
        .background {
            Color.clear
                .alert(jit.finished?.title ?? "", isPresented: Binding(
                    get: { jit.finished != nil && install.flow == nil },
                    set: { if !$0 { jit.finished = nil } }
                )) {
                    Button("OK", role: .cancel) { jit.finished = nil }
                } message: {
                    Text(jit.finished?.message ?? "")
                }
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
