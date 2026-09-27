import SwiftUI
import UniformTypeIdentifiers

/// Pick a store (AltStore by default, or Catalyst), install or refresh it, or sign
/// any IPA with your own Apple ID. The install itself runs in InstallFlowView.
struct InstallView: View {
    @Binding var selectedTab: AppTab
    @StateObject private var controller = InstallController.shared
    @StateObject private var pairings = PairingStore.shared
    @AppStorage(StoreApp.defaultsKey) private var selectedRaw = StoreApp.altstore.rawValue
    @State private var showImporter = false
    @State private var importError: String?
    @State private var vpnActive = LocalDevVPN.isActive
    @Environment(\.scenePhase) private var scenePhase

    private var store: StoreApp { StoreApp(rawValue: selectedRaw) ?? .altstore }

    var body: some View {
        NavigationStack {
            AuroraScreen {
                VStack(spacing: 10) {
                    SectionLabel(title: "Store")
                    storePicker
                }

                hero

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 12) {
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
                    }
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Your Own Apps")
                    customIPACard
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Setup", trailing: "\(readyCount) of 4 ready")
                    checklist
                }

                Text("AltLoad signs apps with your Apple ID and installs them straight onto this iPhone, no computer needed. With a free Apple ID, apps last 7 days. AltLoad reminds you the day before.")
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("Install")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await controller.loadCatalogs() }
                    } label: {
                        Label("Check for updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(controller.isBusy)
                }
            }
            .task {
                if controller.releases.count < StoreApp.allCases.count { await controller.loadCatalogs() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { vpnActive = LocalDevVPN.isActive }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]
            ) { result in
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
            .alert("Couldn't import the IPA", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: selectedRaw)
    }

    // MARK: - Store picker

    private var storePicker: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(StoreApp.allCases) { option in
                    storeTile(option)
                }
            }
        }
    }

    private func storeTile(_ option: StoreApp) -> some View {
        let isSelected = option == store
        return Button {
            selectedRaw = option.rawValue
        } label: {
            HStack(spacing: 10) {
                AppIconView(url: controller.releases[option]?.iconURL, symbol: option.fallbackSymbol, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Aurora.frost)
                    Text(tileDetail(option))
                        .font(.caption2)
                        .foregroundStyle(Aurora.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Aurora.frost : Aurora.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isSelected ? Aurora.violet.opacity(0.55) : Aurora.card.opacity(0.6)).interactive(),
            in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Aurora.violet.opacity(0.7) : Aurora.hairline, lineWidth: 1)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(option.name)
    }

    private func tileDetail(_ option: StoreApp) -> String {
        if let app = controller.installed(option) {
            return controller.updateAvailable(option) ? "Update available" : "Installed \(app.version)"
        }
        if option == .altstore { return "Default" }
        return controller.releases[option].map { "v\($0.version)" } ?? "Not installed"
    }

    // MARK: - Hero

    private var hero: some View {
        GlassCard(padding: 24) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Aurora.violet.opacity(0.5))
                        .frame(width: 120, height: 120)
                        .blur(radius: 38)
                    AppIconView(url: controller.releases[store]?.iconURL, symbol: store.fallbackSymbol, size: 96)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                }

                VStack(spacing: 4) {
                    Text(store.name)
                        .font(.title.bold())
                        .foregroundStyle(Aurora.frost)
                    Text(store.tagline)
                        .font(.footnote)
                        .foregroundStyle(Aurora.lilac.opacity(0.85))
                        .multilineTextAlignment(.center)
                    Text(versionLine)
                        .font(.subheadline)
                        .foregroundStyle(Aurora.secondaryText)
                        .multilineTextAlignment(.center)
                }

                statusChip
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

    @ViewBuilder
    private var statusChip: some View {
        if let app = controller.installed(store) {
            if app.isExpired {
                GlassChip(text: "Expired, refresh to reopen", systemImage: "exclamationmark.triangle.fill", tint: Aurora.danger)
            } else if let days = app.daysLeft {
                GlassChip(text: "Installed \(app.version) · \(days) day\(days == 1 ? "" : "s") left", systemImage: "checkmark.seal.fill", tint: Aurora.success)
            } else {
                GlassChip(text: "Installed \(app.version)", systemImage: "checkmark.seal.fill", tint: Aurora.success)
            }
        } else {
            GlassChip(text: "Not installed", systemImage: "circle.dashed")
        }
    }

    private var primaryTitle: String {
        let latest = controller.releases[store]?.version ?? ""
        guard controller.installed(store) != nil else { return "Install \(store.name) \(latest)" }
        return controller.updateAvailable(store) ? "Update to \(store.name) \(latest)" : "Refresh \(store.name)"
    }

    private var primarySymbol: String {
        guard controller.installed(store) != nil else { return "arrow.down.circle.fill" }
        return controller.updateAvailable(store) ? "sparkles" : "arrow.triangle.2.circlepath"
    }

    // MARK: - Custom IPA

    private var customIPACard: some View {
        Button {
            showImporter = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Aurora.frost)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.tint(Aurora.violet.opacity(0.5)), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Install an IPA")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Aurora.frost)
                    Text("Pick any .ipa. AltLoad signs it with your free Apple ID certificate and installs it.")
                        .font(.footnote)
                        .foregroundStyle(Aurora.secondaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(pairings.selfPairing == nil)
        .opacity(pairings.selfPairing == nil ? 0.5 : 1)
        .glassEffect(.regular.tint(Aurora.card.opacity(0.6)).interactive(), in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Aurora.hairline, lineWidth: 1)
        }
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
                    detail: installedDetail,
                    state: storeState)
            }
        }
    }

    private var storeState: StatusRow.Status {
        guard let app = controller.installed(store) else { return .pending }
        return app.isExpired ? .attention : .done
    }

    private var readyCount: Int {
        var n = 0
        if pairings.selfPairing != nil { n += 1 }
        if vpnActive { n += 1 }
        if !AppleIDStore.email.isEmpty { n += 1 }
        if let app = controller.installed(store), !app.isExpired { n += 1 }
        return n
    }

    private var installedDetail: String {
        guard let app = controller.installed(store) else { return "Not installed yet" }
        return "\(app.version), installed \(app.installedAt.formatted(.relative(presentation: .named)))"
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
