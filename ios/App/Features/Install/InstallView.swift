import SwiftUI
import UniformTypeIdentifiers

/// Pick a store (AltStore, AltStore Beta, SideStore or SideStore + LC), see whether
/// it's really on this iPhone, and install, update or refresh it. The install
/// itself runs in InstallFlowView.
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
                storeMenu

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

                if store.isSideStore, controller.releases[store] == nil, controller.catalogErrors[store] != nil {
                    repositoryDownCard
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Setup", trailing: "\(readyCount) of 4 ready")
                    checklist
                }

                if !controller.apps.isEmpty {
                    yourApps
                }

                Text("AltLoad signs \(store.name) with your Apple ID and installs it straight onto this iPhone. With a free Apple ID it lasts 7 days, and AltLoad reminds you the day before.")
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("Install")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
            .settingsButton()
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

    // MARK: - Store picker

    /// One dropdown for every store, grouped by family.
    private var storeMenu: some View {
        Menu {
            Section("AltStore") {
                menuItem(.altstore, title: "AltStore")
                menuItem(.altstoreBeta, title: "AltStore Beta")
            }
            Section("SideStore") {
                menuItem(.sidestore, title: "SideStore")
                menuItem(.sidestoreNightly, title: "SideStore Nightly")
            }
            Section("SideStore + LiveContainer") {
                menuItem(.sidestoreLC, title: "SideStore + LC")
                menuItem(.sidestoreLCNightly, title: "SideStore + LC Nightly")
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Store")
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                    Text(store.name)
                        .font(.headline)
                        .foregroundStyle(Aurora.frost)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Aurora.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .cardSurface(radius: 18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedRaw)
    }

    private func menuItem(_ option: StoreApp, title: String) -> some View {
        Button {
            selectedRaw = option.rawValue
        } label: {
            if option == store {
                Label(title, systemImage: "checkmark")
            } else if controller.isOnDevice(option) && !option.isNightly {
                Label(title, systemImage: "iphone")
            } else {
                Text(title)
            }
        }
    }

    /// SideStore's repository and source go down now and then.
    private var repositoryDownCard: some View {
        GlassCard(tint: Aurora.ember) {
            VStack(alignment: .leading, spacing: 10) {
                Label("\(store.name)'s repository is down", systemImage: "exclamationmark.icloud.fill")
                    .font(.headline)
                Text(StoreCatalog.newestCachedIPA(store) != nil
                     ? "AltLoad will use the copy it downloaded last time. You can also pick an IPA you have."
                     : "AltLoad tried the source, its mirror and GitHub. Try again later, or pick a \(store.name) IPA you already have.")
                    .font(.subheadline)
                    .foregroundStyle(Aurora.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        Task { await controller.loadCatalog(store) }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AltLoadButtonStyle(prominent: false))
                    Button {
                        showImporter = true
                    } label: {
                        Label("Pick IPA", systemImage: "doc.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AltLoadButtonStyle(prominent: false))
                    .disabled(pairings.selfPairing == nil)
                }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        GlassCard(padding: 22) {
          VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 18) {
                AppIconView(url: controller.releases[store]?.iconURL ?? store.defaultIconURL, symbol: store.fallbackSymbol, size: 84)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.name)
                        .font(.title2.bold())
                        .foregroundStyle(Aurora.frost)
                    Text(store.tagline)
                        .font(.footnote)
                        .foregroundStyle(Aurora.mist)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(versionLine)
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
            .padding(.top, 16)
          }
        }
        .id(store)
        .transition(.blurReplace)
    }

    @ViewBuilder
    private var chips: some View {
        statusChip
        if !entitlements.enabled.isEmpty {
            GlassChip(text: "\(entitlements.enabled.count) entitlement\(entitlements.enabled.count == 1 ? "" : "s")",
                      systemImage: "checkmark.shield.fill", tint: Aurora.sky)
        }
    }

    private var versionLine: String {
        if let release = controller.releases[store] {
            var line = store.isNightly ? "Nightly build" : "Latest \(release.version)"
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
        switch controller.presence[store.base] {
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
        guard controller.isOnDevice(store) else { return store.isNightly ? "Install \(store.name)" : "Install \(store.name) \(latest)" }
        return controller.updateAvailable(store) ? "Update to \(latest)" : "Refresh \(store.name)"
    }

    private var primarySymbol: String {
        guard controller.isOnDevice(store) else { return "arrow.down.circle.fill" }
        return controller.updateAvailable(store) ? "sparkles" : "arrow.triangle.2.circlepath"
    }

    // MARK: - Your apps

    /// Everything AltLoad signed, stores and IPAs, with a pill to refresh each one.
    private var yourApps: some View {
        VStack(spacing: 10) {
            SectionLabel(title: "Your Apps", trailing: "\(controller.apps.count)")
            ForEach(controller.apps) { app in
                appRow(app)
                    .contextMenu {
                        if let target = app.refreshTarget {
                            Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                                controller.begin(target)
                            }
                        }
                        Button("Stop Tracking", systemImage: "minus.circle", role: .destructive) {
                            controller.forget(app)
                        }
                    }
            }
            Text("Long-press an app to stop AltLoad tracking it. Delete it from the Home Screen to uninstall.")
                .font(.caption)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        AppBannerRow(
            name: app.name,
            detail: appDetail(app),
            detailColor: app.isExpired ? Aurora.danger : Aurora.secondaryText,
            iconURL: app.store.flatMap { controller.releases[$0]?.iconURL },
            symbol: app.store?.fallbackSymbol ?? "app.fill"
        ) {
            if let target = app.refreshTarget {
                if app.isExpired {
                    PillButton(caption: "Expired", title: "Refresh", tint: Aurora.danger) { controller.begin(target) }
                } else if let store = app.store, controller.updateAvailable(store) {
                    PillButton(title: "Update") { controller.begin(target) }
                } else if let days = app.daysLeft {
                    PillButton(caption: "Expires in", title: "\(days) day\(days == 1 ? "" : "s")") { controller.begin(target) }
                } else {
                    PillButton(title: "Refresh") { controller.begin(target) }
                }
            } else {
                // An IPA whose cached file is gone: it has to be picked again.
                PillButton(caption: "Expires in", title: "\(app.daysLeft ?? 0) days", tint: Aurora.mist, prominent: false) {}
                    .disabled(true)
            }
        }
    }

    private func appDetail(_ app: InstalledApp) -> String {
        if app.store == nil && app.refreshTarget == nil {
            return "Version \(app.version) · Pick the IPA again to refresh"
        }
        guard let expiration = app.expiration else { return "Version \(app.version)" }
        let when = expiration.formatted(.relative(presentation: .named))
        return "Version \(app.version) · \(app.isExpired ? "Expired" : "Expires") \(when)"
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
