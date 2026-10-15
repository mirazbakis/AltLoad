import SwiftUI
import UniformTypeIdentifiers

/// Pick AltStore or AltStore Beta, see whether it's really on this iPhone, and
/// install, update or refresh it. The install itself runs in InstallFlowView.
struct InstallView: View {
    @Binding var selectedTab: AppTab
    @StateObject private var controller = InstallController.shared
    @StateObject private var pairings = PairingStore.shared
    @ObservedObject private var entitlements = EntitlementSettings.shared
    @AppStorage(StoreApp.defaultsKey) private var selectedRaw = StoreApp.altstore.rawValue
    @State private var showImporter = false
    @State private var importError: String?
    @State private var vpnActive = LocalDevVPN.isActive
    @Environment(\.scenePhase) private var scenePhase

    private var store: StoreApp { StoreApp(rawValue: selectedRaw) ?? .altstore }

    var body: some View {
        NavigationStack {
            AuroraScreen {
                channelPicker

                hero

                if pairings.selfPairing == nil {
                    GlassCard(tint: Aurora.danger) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Pair this iPhone first", systemImage: "link.badge.plus")
                                .font(.headline)
                            Text("AltLoad needs this iPhone's pairing file to talk to it, the way a computer would.")
                                .font(.subheadline)
                                .foregroundStyle(Aurora.secondaryText)
                        }
                    }
                    GlassActionButton(title: "Go to Pair", systemImage: "antenna.radiowaves.left.and.right", prominent: true) {
                        RootView.openPair(tab: $selectedTab)
                    }
                } else {
                    GlassActionButton(title: LocalizedStringKey(primaryTitle), systemImage: primarySymbol, prominent: true) {
                        controller.begin(.store(store))
                    }
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Setup", trailing: "\(readyCount) of 4 ready")
                    checklist
                }

                Text("AltLoad signs AltStore with your Apple ID and installs it straight onto this iPhone. With a free Apple ID it lasts 7 days, and AltLoad reminds you the day before.")
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("Install")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Check for Updates", systemImage: "arrow.clockwise") {
                            Task {
                                await controller.loadCatalogs()
                                await controller.checkDevice(store)
                            }
                        }
                        .disabled(controller.isBusy)
                        Button("Install IPA from Files…", systemImage: "doc.badge.plus") {
                            showImporter = true
                        }
                        .disabled(pairings.selfPairing == nil || controller.isBusy)
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
            .task {
                if controller.releases.count < StoreApp.allCases.count { await controller.loadCatalogs() }
            }
            .task(id: selectedRaw) {
                await controller.checkDevice(store)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                vpnActive = LocalDevVPN.isActive
                Task { await controller.checkDevice(store) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.ipa, .zip, .data]) { result in
                switch result {
                case .success(let url):
                    do {
                        controller.begin(.ipa(try StoreCatalog.importIPA(from: url)))
                    } catch {
                        importError = error.localizedDescription
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Couldn't import the IPA", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: selectedRaw)
    }

    // MARK: - Release / Beta

    private var channelPicker: some View {
        Picker("Build", selection: $selectedRaw) {
            ForEach(StoreApp.allCases) { option in
                Text(option.channel).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }

    // MARK: - Hero

    private var hero: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Aurora.accent.opacity(0.45))
                        .frame(width: 120, height: 120)
                        .blur(radius: 38)
                    AppIconView(url: controller.releases[store]?.iconURL, symbol: store.fallbackSymbol, size: 96)
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                }

                VStack(spacing: 4) {
                    Text(store.name)
                        .font(.title.bold())
                        .foregroundStyle(Aurora.frost)
                    Text(store.tagline)
                        .font(.footnote)
                        .foregroundStyle(Aurora.mist)
                        .multilineTextAlignment(.center)
                    Text(versionLine)
                        .font(.subheadline)
                        .foregroundStyle(Aurora.secondaryText)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 8) {
                    statusChip
                    if !entitlements.enabled.isEmpty {
                        GlassChip(text: "\(entitlements.enabled.count) entitlement\(entitlements.enabled.count == 1 ? "" : "s")",
                                  systemImage: "checkmark.shield.fill", tint: Aurora.sky)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .id(store)
            .transition(.blurReplace)
        }
    }

    private var versionLine: String {
        if let release = controller.releases[store] {
            var line = "Latest \(release.version)"
            if let date = release.date.flatMap(Self.parseDate) {
                line += " · \(date.formatted(date: .abbreviated, time: .omitted))"
            }
            if let min = release.minOSVersion { line += " · iOS \(min)+" }
            return line
        }
        return controller.catalogErrors[store] ?? "Checking the \(store.name) source…"
    }

    /// What's really on the iPhone, from the device check, next to AltLoad's record.
    @ViewBuilder
    private var statusChip: some View {
        let record = controller.installed(store)
        switch controller.presence[store] {
        case .checking where record == nil:
            GlassChip(text: "Checking this iPhone…", systemImage: "magnifyingglass")
        case .missing:
            if record != nil {
                GlassChip(text: "Not on this iPhone any more", systemImage: "exclamationmark.triangle.fill", tint: Aurora.danger)
            } else {
                GlassChip(text: "Not installed", systemImage: "circle.dashed")
            }
        case .installed(let version) where record == nil:
            GlassChip(text: "On this iPhone\(version.map { " · \($0)" } ?? ""), not signed by AltLoad",
                      systemImage: "checkmark.circle", tint: Aurora.sky)
        default:
            if let record {
                if record.isExpired {
                    GlassChip(text: "Expired, refresh to reopen", systemImage: "exclamationmark.triangle.fill", tint: Aurora.danger)
                } else if let days = record.daysLeft {
                    GlassChip(text: "Installed \(record.version) · \(days) day\(days == 1 ? "" : "s") left", systemImage: "checkmark.seal.fill", tint: Aurora.success)
                } else {
                    GlassChip(text: "Installed \(record.version)", systemImage: "checkmark.seal.fill", tint: Aurora.success)
                }
            } else {
                GlassChip(text: "Not installed", systemImage: "circle.dashed")
            }
        }
    }

    private var primaryTitle: String {
        let latest = controller.releases[store]?.version ?? ""
        guard controller.isOnDevice(store) else { return "Install \(store.name) \(latest)" }
        return controller.updateAvailable(store) ? "Update to \(latest)" : "Refresh \(store.name)"
    }

    private var primarySymbol: String {
        guard controller.isOnDevice(store) else { return "arrow.down.circle.fill" }
        return controller.updateAvailable(store) ? "sparkles" : "arrow.triangle.2.circlepath"
    }

    // MARK: - Checklist

    private var checklist: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                StatusRow(
                    title: "Pairing file",
                    detail: pairings.selfPairing.map { "\($0.displayName), saved \($0.date.formatted(.relative(presentation: .named)))" }
                        ?? "Create one in Tools › Pair",
                    state: pairings.selfPairing == nil ? .attention : .done)
                StatusRow(
                    title: "LocalDevVPN",
                    detail: vpnActive ? "Connected, reaching this iPhone at \(LocalDevVPN.targetIP)"
                        : (LocalDevVPN.isInstalled ? "Installed but off. AltLoad will ask you to turn it on" : "Needed for installs. It's free on the App Store"),
                    state: vpnActive ? .done : .pending)
                StatusRow(
                    title: "Apple ID",
                    detail: AppleIDStore.email.isEmpty ? "You'll sign in when you install" : AppleIDStore.email,
                    state: AppleIDStore.email.isEmpty ? .pending : .done)
                StatusRow(
                    title: LocalizedStringKey(store.name),
                    detail: storeDetail,
                    state: storeState)
            }
        }
    }

    private var storeState: StatusRow.Status {
        guard controller.isOnDevice(store) else {
            return controller.installed(store) == nil ? .pending : .attention
        }
        return controller.installed(store)?.isExpired == true ? .attention : .done
    }

    private var readyCount: Int {
        var n = 0
        if pairings.selfPairing != nil { n += 1 }
        if vpnActive { n += 1 }
        if !AppleIDStore.email.isEmpty { n += 1 }
        if storeState == .done { n += 1 }
        return n
    }

    private var storeDetail: String {
        let record = controller.installed(store)
        guard controller.isOnDevice(store) else {
            return record == nil ? "Not installed yet" : "Deleted from this iPhone. Install it again"
        }
        guard let record else {
            return "On this iPhone. Refresh once so AltLoad can keep it signed"
        }
        return "\(controller.installedVersion(store) ?? record.version), installed \(record.installedAt.formatted(.relative(presentation: .named)))"
    }

    private static func parseDate(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}
