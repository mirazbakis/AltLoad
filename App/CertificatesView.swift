import SwiftUI

/// Certificate manager for the signed-in Apple ID's own free development
/// certificates: view their details and revoke them. Also shows the App IDs
/// and registered devices on the team, and a small Tools section.
struct CertificatesView: View {
    @StateObject private var controller = CertificatesController.shared
    @State private var showSignIn = false
    @State private var pendingRevoke: DevCertificate?

    var body: some View {
        NavigationStack {
            AuroraScreen {
                header

                switch controller.phase {
                case .signedOut:
                    signedOut
                case .loading(let stage):
                    loading(stage)
                case .loaded:
                    if let overview = controller.overview {
                        content(overview)
                    }
                case .failed(let message):
                    failure(message)
                }
            }
            .navigationTitle("Certificates")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        controller.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(controller.isBusy || controller.overview == nil)
                }
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet(anisetteURL: InstallController.shared.anisetteURL) { credentials, remember in
                    controller.load(with: credentials, remember: remember)
                }
            }
            .sheet(item: $controller.twoFactor) { prompt in
                TwoFactorSheet(prompt: prompt) { controller.respond($0) }
                    .interactiveDismissDisabled()
            }
            .confirmationDialog(
                "Revoke this certificate?",
                isPresented: Binding(get: { pendingRevoke != nil }, set: { if !$0 { pendingRevoke = nil } }),
                presenting: pendingRevoke
            ) { cert in
                Button("Revoke \(cert.displayName)", role: .destructive) {
                    controller.revoke([cert])
                    pendingRevoke = nil
                }
                Button("Cancel", role: .cancel) { pendingRevoke = nil }
            } message: { _ in
                Text("Apps signed with this certificate will stop opening until they're signed again. This can't be undone.")
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: controller.phase)
        .task {
            if case .signedOut = controller.phase, let saved = controller.savedCredentials {
                controller.load(with: saved)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            GlassBadge(systemImage: "checkmark.seal", tint: Aurora.violet, size: 84)
            Text("Your certificates")
                .font(.title2.bold())
                .foregroundStyle(Aurora.frost)
            Text("Manage the development certificates on your own Apple ID.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    // MARK: - States

    private var signedOut: some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to see your certificates")
                        .font(.headline)
                    Text("AltLoad reads and revokes the development certificates on your Apple ID — the same ones it uses to sign apps. A free account allows a limited number at once.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            GlassActionButton(title: "Sign In", systemImage: "person.crop.circle", prominent: true) {
                if let saved = controller.savedCredentials {
                    controller.load(with: saved)
                } else {
                    showSignIn = true
                }
            }
        }
    }

    private func loading(_ stage: String) -> some View {
        GlassCard {
            HStack(spacing: 16) {
                ProgressRing(value: nil, lineWidth: 6, size: 44)
                Text(stage)
                    .font(.headline)
                    .contentTransition(.opacity)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 14) {
            GlassCard(tint: Aurora.danger) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't load", systemImage: "xmark.octagon.fill")
                        .font(.title3.bold())
                        .foregroundStyle(Aurora.danger)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            GlassActionButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                if let saved = controller.savedCredentials {
                    controller.load(with: saved)
                } else {
                    showSignIn = true
                }
            }
        }
    }

    // MARK: - Loaded content

    private func content(_ overview: AccountOverview) -> some View {
        VStack(spacing: 22) {
            usageCard(overview)

            VStack(spacing: 10) {
                SectionLabel(title: "Certificates", trailing: "\(overview.certificates.count)")
                if overview.certificates.isEmpty {
                    GlassCard {
                        Text("No development certificates yet. One is created the first time you install an app.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(overview.certificates) { cert in
                        certificateCard(cert)
                    }
                }
            }

            if let items = overview.appIds.items, !items.isEmpty {
                VStack(spacing: 10) {
                    SectionLabel(title: "App IDs", trailing: appIdTrailing(overview.appIds))
                    GlassCard {
                        VStack(spacing: 12) {
                            ForEach(items.prefix(8)) { appID in
                                appIdRow(appID)
                                if appID.id != items.prefix(8).last?.id { Divider().overlay(Aurora.frost.opacity(0.1)) }
                            }
                            if items.count > 8 {
                                Text("+ \(items.count - 8) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }

            if !overview.devices.isEmpty {
                VStack(spacing: 10) {
                    SectionLabel(title: "Devices", trailing: "\(overview.devices.count)")
                    GlassCard {
                        VStack(spacing: 12) {
                            ForEach(overview.devices) { device in
                                deviceRow(device)
                                if device.id != overview.devices.last?.id { Divider().overlay(Aurora.frost.opacity(0.1)) }
                            }
                        }
                    }
                }
            }

            toolsSection(overview)

            if let updated = controller.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageCard(_ overview: AccountOverview) -> some View {
        GlassCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(overview.team.name.isEmpty ? "Your team" : overview.team.name)
                        .font(.headline)
                    Text(usageText(overview))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let limit = overview.certificateLimit {
                    ProgressRing(value: Double(overview.certificates.count) / Double(max(limit, 1)),
                                 size: 54, showsPercent: false)
                        .overlay {
                            Text("\(overview.certificates.count)/\(limit)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(Aurora.frost)
                        }
                }
            }
        }
    }

    private func certificateCard(_ cert: DevCertificate) -> some View {
        GlassCard(tint: cert.isExpired ? Aurora.danger : nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(cert.isExpired ? Aurora.danger : Aurora.success)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cert.displayName)
                            .font(.headline)
                        if !cert.type.isEmpty {
                            Text(cert.type)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if cert.isAltLoad {
                        GlassChip(text: "This app", tint: Aurora.violet)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let expiration = cert.expiration {
                        detail("Expires", expiration.formatted(date: .abbreviated, time: .omitted)
                               + (cert.isExpired ? " · expired" : ""))
                    }
                    if !cert.serial.isEmpty { detail("Serial", cert.serial, mono: true) }
                    if !cert.machineName.isEmpty { detail("Machine", cert.machineName) }
                }

                Button(role: .destructive) {
                    pendingRevoke = cert
                } label: {
                    Label("Revoke", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .tint(Aurora.danger)
                .controlSize(.large)
                .disabled(controller.isBusy)
            }
        }
    }

    private func toolsSection(_ overview: AccountOverview) -> some View {
        VStack(spacing: 10) {
            SectionLabel(title: "Tools")
            GlassCard {
                VStack(spacing: 14) {
                    let expired = overview.certificates.filter(\.isExpired)
                    toolRow(
                        title: "Revoke all expired",
                        detail: expired.isEmpty ? "None to revoke" : "\(expired.count) expired certificate\(expired.count == 1 ? "" : "s")",
                        systemImage: "trash.slash",
                        tint: Aurora.danger,
                        disabled: expired.isEmpty || controller.isBusy
                    ) {
                        controller.revoke(expired)
                    }
                    Divider().overlay(Aurora.frost.opacity(0.1))
                    toolRow(
                        title: "Free up a slot",
                        detail: "Revoke the oldest certificate",
                        systemImage: "clock.arrow.circlepath",
                        tint: Aurora.violet,
                        disabled: overview.certificates.isEmpty || controller.isBusy
                    ) {
                        if let oldest = overview.certificates.min(by: { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }) {
                            pendingRevoke = oldest
                        }
                    }
                    Divider().overlay(Aurora.frost.opacity(0.1))
                    toolRow(
                        title: "Sign out",
                        detail: AppleIDStore.email,
                        systemImage: "person.crop.circle.badge.xmark",
                        tint: Aurora.lilac,
                        disabled: controller.isBusy
                    ) {
                        controller.signOut()
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func appIdRow(_ appID: DevAppID) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "app.badge")
                .foregroundStyle(Aurora.lilac)
            VStack(alignment: .leading, spacing: 1) {
                Text(appID.name).font(.subheadline.weight(.medium))
                Text(appID.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private func deviceRow(_ device: DevDevice) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone.gen3")
                .foregroundStyle(Aurora.lilac)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name.isEmpty ? "Device" : device.name).font(.subheadline.weight(.medium))
                Text(device.udid).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private func toolRow(title: LocalizedStringKey, detail: String, systemImage: String, tint: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.tint(tint.opacity(0.22)), in: .circle)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Aurora.frost)
                    if !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func detail(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(mono ? .caption.monospaced() : .caption)
                .foregroundStyle(Aurora.frost)
                .textSelection(.enabled)
        }
    }

    private func usageText(_ overview: AccountOverview) -> String {
        var parts: [String] = []
        if let limit = overview.certificateLimit {
            parts.append("\(overview.certificates.count) of \(limit) certificates")
        } else {
            parts.append("\(overview.certificates.count) certificates")
        }
        if let available = overview.appIds.available, let max = overview.appIds.max {
            parts.append("\(max - available)/\(max) App IDs")
        }
        return parts.joined(separator: " · ")
    }

    private func appIdTrailing(_ appIds: AccountOverview.AppIDs) -> String {
        guard let items = appIds.items else { return "" }
        if let max = appIds.max { return "\(items.count)/\(max)" }
        return "\(items.count)"
    }
}
