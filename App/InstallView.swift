import SwiftUI
import UniformTypeIdentifiers

struct InstallView: View {
    @Binding var selectedTab: AppTab
    @StateObject private var controller = InstallController.shared
    @StateObject private var pairings = PairingStore.shared
    @State private var showSignIn = false
    @State private var showImporter = false
    @State private var pendingIPA: URL?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            AuroraScreen {
                hero

                GlassEffectContainer(spacing: 16) {
                    phaseContent
                        .id(phaseKey)
                        .transition(.blurReplace.combined(with: .scale(0.97)))
                }

                checklist

                Text("AltLoad signs AltStore with your Apple ID and installs it straight onto this iPhone, no computer needed. With a free Apple ID, apps last 7 days. AltLoad reminds you the day before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("Install")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await controller.loadCatalog() }
                    } label: {
                        Label("Check for updates", systemImage: "arrow.clockwise")
                    }
                    .disabled(controller.isBusy)
                }
            }
            .task {
                if controller.latest == nil { await controller.loadCatalog() }
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet(anisetteURL: controller.anisetteURL) { credentials, remember in
                    controller.install(with: credentials, remember: remember, ipa: pendingIPA)
                    pendingIPA = nil
                }
            }
            .sheet(item: $controller.twoFactor) { prompt in
                TwoFactorSheet(prompt: prompt) { controller.respond($0) }
                    .interactiveDismissDisabled()
            }
            .sheet(item: $controller.revoke) { prompt in
                RevokeSheet(prompt: prompt) { controller.respond($0) }
                    .interactiveDismissDisabled()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]
            ) { result in
                switch result {
                case .success(let url):
                    do {
                        pendingIPA = try AltStoreCatalog.importIPA(from: url)
                        showSignIn = true
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
        .animation(.spring(duration: 0.5, bounce: 0.2), value: controller.phase)
        .sensoryFeedback(trigger: controller.phase) { _, newPhase in
            switch newPhase {
            case .success: return .success
            case .failed: return .error
            default: return nil
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 14) {
            AsyncImage(url: controller.latest?.iconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Aurora.accentGradient)
            }
            .frame(width: 84, height: 84)
            .clipShape(.rect(cornerRadius: 20))
            .padding(10)
            .glassEffect(.regular.tint(Aurora.violet.opacity(0.35)).interactive(), in: .rect(cornerRadius: 30))

            Text("AltStore")
                .font(.largeTitle.bold())
                .foregroundStyle(Aurora.frost)

            Text(versionLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            statusChip
        }
        .padding(.top, 4)
    }

    private var versionLine: String {
        if let release = controller.latest {
            var line = "Latest \(release.version)"
            if let date = release.date.flatMap(Self.parseDate) {
                line += " · \(date.formatted(date: .abbreviated, time: .omitted))"
            }
            if let min = release.minOSVersion { line += " · iOS \(min)+" }
            return line
        }
        return controller.catalogError ?? "Checking the AltStore source…"
    }

    @ViewBuilder
    private var statusChip: some View {
        if let app = controller.installed {
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

    // MARK: - Phase content

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .idle:
            VStack(spacing: 14) {
                if pairings.selfPairing == nil {
                    GlassCard(tint: Aurora.danger) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Pair this iPhone first", systemImage: "link.badge.plus")
                                .font(.headline)
                            Text("AltLoad needs this iPhone's pairing file to talk to it, the way a computer would.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    GlassActionButton(title: "Go to Pair", systemImage: "antenna.radiowaves.left.and.right", prominent: true) {
                        selectedTab = .pair
                    }
                } else {
                    GlassActionButton(title: LocalizedStringKey(primaryTitle), systemImage: primarySymbol, prominent: true) {
                        pendingIPA = nil
                        showSignIn = true
                    }
                    GlassActionButton(title: "Install from IPA File…", systemImage: "doc.badge.plus") {
                        showImporter = true
                    }
                }
            }

        case .checking:
            GlassCard {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Getting ready…").foregroundStyle(.secondary)
                }
            }

        case .downloading(let fraction):
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Downloading AltStore \(controller.latest?.version ?? "")")
                        .font(.headline)
                    ProgressView(value: fraction)
                        .tint(Aurora.lilac)
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

        case .working(let stage, let fraction):
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            if fraction == nil { ProgressView() }
                            Text(stage)
                                .font(.headline)
                                .contentTransition(.opacity)
                        }
                        if let fraction {
                            ProgressView(value: fraction)
                                .tint(Aurora.lilac)
                        }
                        Text("Keep AltLoad open until this finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GlassActionButton(title: "Cancel") { controller.cancel() }
            }

        case .success(let app):
            VStack(spacing: 14) {
                GlassCard(tint: Aurora.success) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(app.name) \(app.version) installed", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold())
                            .foregroundStyle(Aurora.success)
                        if let expiration = app.expiration {
                            Text("Signed until \(expiration.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("First launch: if iOS says the developer isn't trusted, open **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                GlassActionButton(title: "Done") { controller.reset() }
            }

        case .failed(let message):
            VStack(spacing: 14) {
                GlassCard(tint: Aurora.danger) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Install failed", systemImage: "xmark.octagon.fill")
                            .font(.title3.bold())
                            .foregroundStyle(Aurora.danger)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                GlassActionButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                    controller.reset()
                }
            }
        }
    }

    private var primaryTitle: String {
        let latest = controller.latest?.version ?? ""
        guard controller.installed != nil else { return "Install AltStore \(latest)" }
        return controller.updateAvailable ? "Update to AltStore \(latest)" : "Refresh AltStore"
    }

    private var primarySymbol: String {
        guard controller.installed != nil else { return "arrow.down.circle.fill" }
        return controller.updateAvailable ? "sparkles" : "arrow.triangle.2.circlepath"
    }

    // MARK: - Checklist

    private var checklist: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                StatusRow(
                    title: "Pairing file",
                    detail: pairings.selfPairing.map { "\($0.displayName), saved \($0.date.formatted(.relative(presentation: .named)))" }
                        ?? "Create one in the Pair tab",
                    state: pairings.selfPairing == nil ? .attention : .done)
                StatusRow(
                    title: "Apple ID",
                    detail: AppleIDStore.email.isEmpty ? "You'll sign in when you install" : AppleIDStore.email,
                    state: AppleIDStore.email.isEmpty ? .pending : .done)
                StatusRow(
                    title: "AltStore",
                    detail: installedDetail,
                    state: controller.installed == nil ? .pending : (controller.installed!.isExpired ? .attention : .done))
            }
        }
    }

    private var installedDetail: String {
        guard let app = controller.installed else { return "Not installed yet" }
        return "\(app.version), installed \(app.installedAt.formatted(.relative(presentation: .named)))"
    }

    private var phaseKey: String {
        switch controller.phase {
        case .idle: "idle"
        case .checking: "checking"
        case .downloading: "downloading"
        case .working: "working"
        case .success: "success"
        case .failed: "failed"
        }
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
