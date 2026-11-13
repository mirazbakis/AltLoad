import SwiftUI

/// Tools › JIT: opens an app with AltLoad's debugger attached. AltLoad stays with
/// it while it asks for JIT memory (through the app's script), then lets go.
/// Works for apps signed for development (anything AltLoad or AltStore installed).
struct JITView: View {
    @ObservedObject private var pairings = PairingStore.shared
    @ObservedObject private var jit = JITCenter.shared
    @ObservedObject private var scripts = JITScripts.shared

    @State private var apps: [DeviceOps.DeviceApp] = []
    @State private var loading = false
    @State private var stage: String?
    @State private var loadError: String?
    @State private var search = ""
    @State private var showAll = false
    @State private var linkCopied = false

    var body: some View {
        AuroraScreen {
            GlassCard(padding: 20) {
                HStack(spacing: 14) {
                    GlassBadge(systemImage: "bolt.fill", tint: Aurora.accent, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable JIT").font(.headline)
                        Text("Opens the app with AltLoad's debugger attached. AltLoad stays with it while it asks for JIT memory, which emulators need on newer iPhones, then lets go.")
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                }
            }

            if let active = jit.active {
                activeCard(active)
            }

            if loading {
                GlassCard {
                    HStack(spacing: 14) {
                        ProgressRing(value: nil, lineWidth: 4, size: 28, showsPercent: false)
                        Text(stage ?? String(localized: "Reading installed apps…")).font(.subheadline)
                    }
                }
            } else if let loadError {
                GlassCard(tint: Aurora.danger) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "Couldn't read the apps"), systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                        if !LocalDevVPN.isActive {
                            GlassActionButton(title: LocalDevVPN.isInstalled ? "Turn On LocalDevVPN" : "Get LocalDevVPN",
                                              systemImage: "power", prominent: true) { LocalDevVPN.turnOn() }
                        }
                    }
                }
            } else if apps.isEmpty {
                GlassActionButton(title: "Load Installed Apps", systemImage: "arrow.clockwise", prominent: true) {
                    Task { await load() }
                }
                .disabled(pairings.selfPairing == nil)
            } else {
                VStack(spacing: 10) {
                    SectionLabel(title: showAll ? "All apps" : "Development-signed apps", trailing: "\(filtered.count)")
                    ForEach(filtered) { app in
                        appRow(app)
                    }
                    Toggle(String(localized: "Show apps that can't use JIT"), isOn: $showAll)
                        .font(.footnote)
                        .padding(.horizontal, 4)
                    Text("Long-press an app to pick the script it uses.")
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }

            linksCard
        }
        .navigationTitle(String(localized: "JIT"))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: String(localized: "Search apps"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    JITScriptsView()
                } label: {
                    Label(String(localized: "Scripts"), systemImage: "curlybraces")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Label(String(localized: "Reload"), systemImage: "arrow.clockwise")
                }
                .disabled(loading || pairings.selfPairing == nil)
            }
        }
        .task {
            if apps.isEmpty, pairings.selfPairing != nil, LocalDevVPN.isActive { await load() }
        }
    }

    // MARK: - Pieces

    private func activeCard(_ active: JITCenter.Active) -> some View {
        GlassCard(tint: Aurora.accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ProgressRing(value: nil, lineWidth: 4, size: 28, showsPercent: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "JIT for \(active.appName)")).font(.headline)
                        Text(active.stage)
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                        Text(String(localized: "Script: \(active.scriptName)"))
                            .font(.caption)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                }
                if let last = jit.log.last {
                    Text(last)
                        .font(.caption.monospaced())
                        .foregroundStyle(Aurora.secondaryText)
                        .lineLimit(2)
                }
                GlassActionButton(title: "Stop", systemImage: "stop.fill") { jit.stop() }
            }
        }
    }

    private func appRow(_ app: DeviceOps.DeviceApp) -> some View {
        let script = scripts.script(for: app.bundleID)
        return AppBannerRow(
            name: app.name,
            detail: script.builtIn ? app.bundleID : "\(app.bundleID) · \(script.name)",
            symbol: "app.fill"
        ) {
            PillButton(title: String(localized: "JIT"), tint: Aurora.accent) {
                jit.start(bundleID: app.bundleID, appName: app.name)
            }
            .disabled(jit.isRunning || !app.debuggable)
            .opacity(app.debuggable ? 1 : 0.4)
        }
        .contextMenu {
            Section(String(localized: "Script")) {
                ForEach(scripts.all) { option in
                    Button {
                        scripts.assign(option.name, to: app.bundleID)
                    } label: {
                        if option.name == script.name {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            }
            Button(String(localized: "Copy JIT Link"), systemImage: "link") {
                UIPasteboard.general.string = "altload://enable-jit?bundle-id=\(app.bundleID)"
            }
        }
    }

    private var linksCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "From other apps and Shortcuts"), systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                Text("Other apps can ask for JIT with a link, and Shortcuts has an Enable JIT action. AltLoad asks you before it follows a link.")
                    .font(.footnote)
                    .foregroundStyle(Aurora.secondaryText)
                Text(verbatim: "altload://enable-jit?bundle-id=com.example.app")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("Add &script-name= to pick an imported script, or &script-data= with a script in Base64.")
                    .font(.caption)
                    .foregroundStyle(Aurora.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var filtered: [DeviceOps.DeviceApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return apps
            .filter { showAll || $0.debuggable }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func load() async {
        loading = true
        loadError = nil
        stage = nil
        defer { loading = false; stage = nil }
        do {
            apps = try await DeviceOps.listApps { text, _ in stage = text }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Tools › JIT › Scripts: AltLoad's script and the ones you imported.
struct JITScriptsView: View {
    @ObservedObject private var scripts = JITScripts.shared
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        AuroraScreen {
            GlassCard {
                Text("A script decides how AltLoad answers an app while it's attached. AltLoad's own handles the usual JIT requests, and apps can send it more. Import a .js file to give an app its own; scripts can call send_command, continue_for, prepare_memory_region, get_pid, get_bundle_id and log.")
                    .font(.footnote)
                    .foregroundStyle(Aurora.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 10) {
                SectionLabel(title: "Scripts", trailing: "\(scripts.all.count)")
                ForEach(scripts.all) { script in
                    NavigationLink {
                        JITScriptDetailView(script: script)
                    } label: {
                        AppBannerRow(
                            name: script.name,
                            detail: script.builtIn ? String(localized: "Built in") : usedBy(script),
                            symbol: script.builtIn ? "bolt.fill" : "curlybraces"
                        ) {
                            Image(systemName: "chevron.right").foregroundStyle(Aurora.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !script.builtIn {
                            Button(String(localized: "Delete"), systemImage: "trash", role: .destructive) {
                                scripts.delete(script)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Scripts"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: {
                    Label(String(localized: "Import"), systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.javaScript, .plainText]) { result in
            do {
                try scripts.importScript(from: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .alert(String(localized: "Couldn't import the script"), isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private func usedBy(_ script: JITScript) -> String {
        let apps = scripts.apps(using: script)
        return apps.isEmpty ? String(localized: "Not used by any app") : String(localized: "Used by \(apps.joined(separator: ", "))")
    }
}

/// One script's source.
struct JITScriptDetailView: View {
    let script: JITScript
    @ObservedObject private var scripts = JITScripts.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(script.source)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppBackground())
        .navigationTitle(script.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if !script.builtIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        scripts.delete(script)
                        dismiss()
                    } label: {
                        Label(String(localized: "Delete"), systemImage: "trash")
                    }
                }
            }
        }
    }
}
