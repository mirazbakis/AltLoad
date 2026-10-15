import SwiftUI

/// Tools › JIT: launches an app under debugserver and detaches, so it can JIT.
/// Works for apps signed for development (anything AltLoad or AltStore installed).
struct JITView: View {
    @ObservedObject private var pairings = PairingStore.shared

    @State private var apps: [DeviceOps.DeviceApp] = []
    @State private var loading = false
    @State private var stage: String?
    @State private var loadError: String?
    @State private var working: String?
    @State private var result: Result?
    @State private var search = ""
    @State private var showAll = false

    struct Result: Identifiable {
        let id = UUID()
        let success: Bool
        let message: String
    }

    var body: some View {
        AuroraScreen {
            GlassCard(padding: 20) {
                HStack(spacing: 14) {
                    GlassBadge(systemImage: "bolt.fill", tint: Aurora.accent, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable JIT").font(.headline)
                        Text("Opens the app with a debugger attached for a moment, which lets emulators and other JIT apps run at full speed until you close them.")
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                }
            }

            if let working {
                GlassCard {
                    HStack(spacing: 14) {
                        ProgressRing(value: nil, lineWidth: 4, size: 28, showsPercent: false)
                        Text(stage ?? "Enabling JIT for \(working)…").font(.subheadline)
                    }
                }
            }

            if loading {
                GlassCard {
                    HStack(spacing: 14) {
                        ProgressRing(value: nil, lineWidth: 4, size: 28, showsPercent: false)
                        Text(stage ?? "Reading installed apps…").font(.subheadline)
                    }
                }
            } else if let loadError {
                GlassCard(tint: Aurora.danger) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Couldn't read the apps", systemImage: "exclamationmark.triangle.fill")
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
                        AppBannerRow(name: app.name, detail: app.bundleID, symbol: "app.fill") {
                            PillButton(title: "JIT", tint: Aurora.accent) { enable(app) }
                                .disabled(working != nil || !app.debuggable)
                                .opacity(app.debuggable ? 1 : 0.4)
                        }
                    }
                    Toggle("Show apps that can't use JIT", isOn: $showAll)
                        .font(.footnote)
                        .padding(.horizontal, 4)
                }
            }
        }
        .navigationTitle("JIT")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search apps")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(loading || working != nil || pairings.selfPairing == nil)
            }
        }
        .task {
            if apps.isEmpty, pairings.selfPairing != nil, LocalDevVPN.isActive { await load() }
        }
        .alert(item: $result) { result in
            Alert(title: Text(result.success ? "JIT enabled" : "Couldn't enable JIT"),
                  message: Text(result.message),
                  dismissButton: .default(Text("OK")))
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

    private func enable(_ app: DeviceOps.DeviceApp) {
        working = app.name
        stage = nil
        Task {
            defer { working = nil; stage = nil }
            do {
                try await DeviceOps.enableJIT(app.bundleID) { text, _ in stage = text }
                result = Result(success: true, message: "\(app.name) is open with JIT. It keeps JIT until you close it.")
            } catch {
                result = Result(success: false, message: error.localizedDescription)
            }
        }
    }
}
