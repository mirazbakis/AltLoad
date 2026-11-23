import SwiftUI

/// Install › More › Sources: AltStore-format sources and their apps. Installing one
/// downloads its IPA and runs the same flow as an IPA from Files.
struct SourcesView: View {
    @StateObject private var sources = AppSources.shared
    @StateObject private var controller = InstallController.shared
    @StateObject private var pairings = PairingStore.shared
    @State private var link = ""
    @State private var adding = false
    @State private var addError: String?
    @State private var installError: String?

    var body: some View {
        AuroraScreen {
            addCard

            if !sources.updates.isEmpty {
                VStack(spacing: 10) {
                    SectionLabel(title: "Updates", trailing: "\(sources.updates.count)")
                    ForEach(sources.updates) { appRow($0) }
                }
            }

            ForEach(sources.sources) { source in
                VStack(spacing: 10) {
                    SectionLabel(title: LocalizedStringKey(source.name), trailing: "\(source.apps.count)")
                    if source.apps.isEmpty {
                        GlassCard {
                            Text("This source lists no apps.")
                                .font(.subheadline)
                                .foregroundStyle(Aurora.secondaryText)
                        }
                    }
                    ForEach(source.apps) { appRow($0) }
                }
            }

            if !sources.urls.isEmpty {
                yourSources
            }
        }
        .navigationTitle(String(localized: "Sources"))
        .toolbarTitleDisplayMode(.inline)
        .navigationDestination(for: SourceAppRoute.self) { route in
            SourceAppView(appID: route.id, installError: $installError)
        }
        .refreshable { await sources.refresh() }
        .task {
            if sources.sources.isEmpty, !sources.urls.isEmpty { await sources.refresh() }
        }
        .alert(String(localized: "Couldn't install the app"), isPresented: Binding(get: { installError != nil }, set: { if !$0 { installError = nil } })) {
            Button(String(localized: "OK")) { installError = nil }
        } message: {
            Text(installError ?? "")
        }
    }

    // MARK: - Add

    private var addCard: some View {
        CardSection(title: "Add a Source", symbol: "plus.circle.fill") {
            TextField("https://…", text: $link)
                .font(.subheadline.monospaced())
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { add(link) }
                .inputField()
            Button {
                add(link)
            } label: {
                Label(adding ? String(localized: "Checking…") : String(localized: "Add Source"), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AltLoadButtonStyle())
            .disabled(adding || link.trimmingCharacters(in: .whitespaces).isEmpty)

            if let addError {
                Text(addError)
                    .font(.caption)
                    .foregroundStyle(Aurora.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let suggestions = AppSources.suggestions.filter { !sources.contains($0.url) }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.url) { item in
                            Button {
                                add(item.url.absoluteString)
                            } label: {
                                Label(item.name, systemImage: "plus")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Aurora.frost)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Aurora.raised, in: .capsule)
                                    .overlay { Capsule().strokeBorder(Aurora.hairline, lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                            .disabled(adding)
                        }
                    }
                }
            }

            Text("Paste a source's https link, or an altstore:// or sidestore:// source link. AltLoad checks it before saving. Apps you install from a source refresh like any other app, and show Update when the source has a newer version.")
                .font(.caption)
                .foregroundStyle(Aurora.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func add(_ input: String) {
        guard !adding else { return }
        adding = true
        addError = nil
        Task {
            do {
                try await sources.add(input)
                link = ""
            } catch {
                addError = error.localizedDescription
            }
            adding = false
        }
    }

    // MARK: - Apps

    private func appRow(_ app: SourceApp) -> some View {
        NavigationLink(value: SourceAppRoute(id: app.id)) {
            AppBannerRow(name: app.name, detail: detail(app), iconURL: app.iconURL) {
                SourceInstallPill(app: app, installError: $installError)
            }
        }
        .buttonStyle(.plain)
    }

    private func detail(_ app: SourceApp) -> String {
        let version = app.latest?.version ?? ""
        if let developer = app.developer, !developer.isEmpty { return "\(developer) · \(version)" }
        return version
    }

    // MARK: - Your sources

    private var yourSources: some View {
        CardSection(title: "Your Sources", symbol: "list.bullet") {
            ForEach(sources.urls, id: \.absoluteString) { url in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sources.sources.first { $0.url == url }?.name ?? url.host ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Aurora.frost)
                        Text(url.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(Aurora.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let error = sources.errors[url.absoluteString] {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Aurora.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Copy Link"))
                    Button(role: .destructive) {
                        sources.remove(url)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .tint(Aurora.danger)
                    .accessibilityLabel(String(localized: "Remove Source"))
                }
                .frame(minHeight: 44)
            }
            Text("Pull down to check your sources again.")
                .font(.caption)
                .foregroundStyle(Aurora.secondaryText)
        }
    }
}

struct SourceAppRoute: Hashable {
    let id: String
}

/// Install, Update or Installed, with the download's progress while it runs.
private struct SourceInstallPill: View {
    let app: SourceApp
    @Binding var installError: String?
    @ObservedObject private var sources = AppSources.shared
    @ObservedObject private var controller = InstallController.shared
    @ObservedObject private var pairings = PairingStore.shared

    var body: some View {
        if let download = sources.download, download.appID == app.id {
            PillButton(caption: String(localized: "Downloading"), title: "\(Int(download.fraction * 100))%", prominent: false) {}
                .disabled(true)
        } else if sources.hasUpdate(app) {
            PillButton(title: String(localized: "Update")) { start() }
                .disabled(!canInstall)
        } else if sources.installed(app) != nil {
            PillButton(title: String(localized: "Reinstall"), prominent: false) { start() }
                .disabled(!canInstall)
        } else {
            PillButton(title: String(localized: "Install")) { start() }
                .disabled(!canInstall)
        }
    }

    private var canInstall: Bool {
        pairings.selfPairing != nil && !controller.isBusy && sources.download == nil
    }

    private func start() {
        guard let version = app.latest else { return }
        SourceInstall.run(app, version, installError: $installError)
    }
}

enum SourceInstall {
    /// Downloads the IPA, then opens the install flow for it.
    @MainActor
    static func run(_ app: SourceApp, _ version: SourceVersion, installError: Binding<String?>) {
        Task {
            do {
                let ipa = try await AppSources.shared.downloadIPA(app, version)
                InstallController.shared.begin(.ipa(ipa))
            } catch {
                AppLog.shared.error(.install, "Couldn't download \(app.name) \(version.version): \(error.localizedDescription)")
                installError.wrappedValue = error.localizedDescription
            }
        }
    }
}

/// One app from a source: what's new, its description and every version.
struct SourceAppView: View {
    let appID: String
    @Binding var installError: String?
    @ObservedObject private var sources = AppSources.shared
    @ObservedObject private var controller = InstallController.shared
    @ObservedObject private var pairings = PairingStore.shared
    @State private var olderVersion: SourceVersion?

    private var app: SourceApp? {
        sources.sources.flatMap(\.apps).first { $0.id == appID }
    }

    var body: some View {
        AuroraScreen {
            if let app {
                content(app)
            } else {
                GlassCard {
                    Text("This app is no longer in your sources.")
                        .font(.subheadline)
                        .foregroundStyle(Aurora.secondaryText)
                }
            }
        }
        .navigationTitle(app?.name ?? "")
        .toolbarTitleDisplayMode(.inline)
        .confirmationDialog(String(localized: "Install an older version?"), isPresented: Binding(get: { olderVersion != nil }, set: { if !$0 { olderVersion = nil } }), titleVisibility: .visible, presenting: olderVersion) { version in
            Button(String(localized: "Install \(version.version)")) {
                if let app { SourceInstall.run(app, version, installError: $installError) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("An older version may not open your data from a newer one.")
        }
    }

    @ViewBuilder
    private func content(_ app: SourceApp) -> some View {
        GlassCard(padding: 22) {
            HStack(alignment: .center, spacing: 18) {
                AppIconView(url: app.iconURL, size: 84)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                        .font(.title2.bold())
                        .foregroundStyle(Aurora.frost)
                    if let developer = app.developer {
                        Text(developer)
                            .font(.footnote)
                            .foregroundStyle(Aurora.mist)
                    }
                    Text(versionLine(app))
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }

        if let latest = app.latest {
            if let download = sources.download, download.appID == app.id {
                ProgressView(value: download.fraction) {
                    Text("Downloading \(app.name)…").font(.footnote)
                }
                .tint(Aurora.accent)
            } else {
                GlassActionButton(title: LocalizedStringKey(primaryTitle(app, latest)), systemImage: "arrow.down.circle.fill", prominent: true) {
                    SourceInstall.run(app, latest, installError: $installError)
                }
                .disabled(pairings.selfPairing == nil || controller.isBusy || sources.download != nil)
            }
            if pairings.selfPairing == nil {
                Text("Pair this iPhone in Tools › Pair before installing.")
                    .font(.caption)
                    .foregroundStyle(Aurora.secondaryText)
            }
            if let min = latest.minOSVersion, AppSources.isNewer(min, than: UIDevice.current.systemVersion) {
                Label(String(localized: "Needs iOS \(min) or later."), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Aurora.ember)
            }

            if let notes = latest.notes, !notes.isEmpty {
                CardSection(title: "What's New", symbol: "sparkles") {
                    markdown(notes)
                }
            }
        }

        if let text = app.description ?? app.subtitle, !text.isEmpty {
            CardSection(title: "About", symbol: "info.circle.fill") {
                markdown(text)
            }
        }

        if app.versions.count > 1 {
            CardSection(title: "Versions", symbol: "clock.arrow.circlepath") {
                ForEach(app.versions.dropFirst()) { version in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(version.version)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Aurora.frost)
                            if let date = version.date {
                                Text(String(date.prefix(10)))
                                    .font(.caption)
                                    .foregroundStyle(Aurora.secondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                        Button(String(localized: "Install")) { olderVersion = version }
                            .font(.footnote.weight(.semibold))
                            .disabled(pairings.selfPairing == nil || controller.isBusy || sources.download != nil)
                    }
                    .frame(minHeight: 40)
                }
            }
        }
    }

    private func primaryTitle(_ app: SourceApp, _ latest: SourceVersion) -> String {
        if sources.hasUpdate(app) { return String(localized: "Update to \(latest.version)") }
        if sources.installed(app) != nil { return String(localized: "Reinstall \(latest.version)") }
        return String(localized: "Install \(latest.version)")
    }

    private func versionLine(_ app: SourceApp) -> String {
        var line = app.latest.map { String(localized: "Latest \($0.version)") } ?? ""
        if let installed = sources.installed(app) {
            line += String(localized: " · Installed \(installed.version)")
        }
        return line
    }

    /// Release notes and descriptions use Markdown; headings and lists stay as written.
    private func markdown(_ text: String) -> some View {
        let attributed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        return Text(attributed)
            .font(.subheadline)
            .foregroundStyle(Aurora.frost)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
