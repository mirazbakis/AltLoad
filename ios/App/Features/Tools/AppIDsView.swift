import SwiftUI

/// Tools › App IDs: every App ID on the signed-in Apple ID's team, how many of the
/// weekly limit are used, and when each one frees up. Loads through the same
/// account session as Certificates, so signing in once covers both.
struct AppIDsView: View {
    @StateObject private var controller = CertificatesController.shared
    @State private var showSignIn = false
    @State private var search = ""

    var body: some View {
        AuroraScreen {
            switch controller.phase {
            case .signedOut:
                signedOut
            case .loading(let stage):
                if let overview = controller.overview {
                    content(overview)
                } else {
                    loading(stage)
                }
            case .loaded:
                if let overview = controller.overview {
                    content(overview)
                }
            case .failed(let message):
                failure(message)
            }
        }
        .navigationTitle("App IDs")
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $search, prompt: "Search App IDs")
        .refreshable { reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if controller.isBusy {
                    ProgressView()
                } else {
                    Button {
                        reload()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showSignIn) {
            SignInSheet(anisetteURL: InstallController.shared.anisetteURL) { credentials, remember in
                controller.load(with: credentials, remember: remember)
            }
            .auroraTheme()
        }
        .fullScreenCover(item: $controller.twoFactor) { prompt in
            TwoFactorSheet(prompt: prompt) { controller.respond($0) }
                .auroraTheme()
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: controller.phase)
        .task {
            if case .signedOut = controller.phase, let saved = controller.savedCredentials {
                controller.load(with: saved)
            }
        }
    }

    /// Refreshes with the current session, or signs in again with the saved password.
    private func reload() {
        guard !controller.isBusy else { return }
        if controller.overview != nil {
            controller.refresh()
        } else if let saved = controller.savedCredentials {
            controller.load(with: saved)
        } else {
            showSignIn = true
        }
    }

    // MARK: - States

    private var signedOut: some View {
        VStack(spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to see your App IDs")
                        .font(.headline)
                    Text("Every app and extension AltLoad signs uses an App ID. A free Apple ID can have 10 at a time, and each one frees up 7 days after it was made.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            GlassActionButton(title: "Sign In", systemImage: "person.crop.circle", prominent: true) {
                reload()
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

    // MARK: - Loaded

    private func content(_ overview: AccountOverview) -> some View {
        let items = (overview.appIds.items ?? []).sorted { ($0.expiration ?? .distantFuture) < ($1.expiration ?? .distantFuture) }
        let query = search.trimmingCharacters(in: .whitespaces)
        let shown = query.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.identifier.localizedCaseInsensitiveContains(query)
        }

        return VStack(spacing: 22) {
            usageCard(overview.appIds, items: items)

            if let error = overview.appIds.error {
                GlassCard(tint: Aurora.danger) {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            VStack(spacing: 10) {
                SectionLabel(title: "App IDs", trailing: "\(shown.count)")
                if shown.isEmpty {
                    GlassCard {
                        Text(items.isEmpty ? "No App IDs yet. One is made the first time you install an app."
                                           : "Nothing matches \"\(query)\".")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    GlassCard {
                        VStack(spacing: 12) {
                            ForEach(shown) { appID in
                                row(appID)
                                if appID.id != shown.last?.id { Divider().overlay(Aurora.frost.opacity(0.1)) }
                            }
                        }
                    }
                }
            }

            Text("Apple doesn't let free Apple IDs delete App IDs. They free up on their own 7 days after they were made. To use fewer, set App Extensions to Keep, Use Main Profile or Remove Extensions when you install.")
                .font(.caption)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            if let updated = controller.lastUpdated {
                Text("Updated \(updated.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func usageCard(_ appIds: AccountOverview.AppIDs, items: [DevAppID]) -> some View {
        let max = appIds.max
        let used = max.flatMap { m in appIds.available.map { m - $0 } } ?? items.count
        let nextFree = items.compactMap(\.expiration).filter { $0 > .now }.min()
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(used)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Aurora.frost)
                        .contentTransition(.numericText())
                    if let max {
                        Text("of \(max) used")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("in use")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let max, max > 0 {
                    GlassProgressBar(value: min(1, Double(used) / Double(max)))
                }
                if let available = appIds.available {
                    Label(available > 0 ? "\(available) available now" : "None available right now",
                          systemImage: available > 0 ? "checkmark.circle.fill" : "clock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(available > 0 ? Aurora.success : Aurora.ember)
                }
                if let nextFree {
                    Text("Next one frees up \(nextFree.formatted(.relative(presentation: .named))).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ appID: DevAppID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge")
                .font(.title3)
                .foregroundStyle(Aurora.mist)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(appID.name.isEmpty ? "Unnamed" : appID.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Aurora.frost)
                Text(appID.identifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let expiration = appID.expiration {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(expiration < .now ? "Freed" : "Frees up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(expiration.formatted(.relative(presentation: .numeric)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Aurora.frost)
                }
            }
        }
        .contextMenu {
            Button("Copy Identifier", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = appID.identifier
            }
        }
    }
}

#Preview {
    NavigationStack { AppIDsView() }
        .auroraTheme()
}
