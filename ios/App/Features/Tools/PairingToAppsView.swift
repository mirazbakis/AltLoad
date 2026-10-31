import SwiftUI

/// Copies this iPhone's pairing file into another installed app (SideStore,
/// StikDebug…) over house_arrest, through LocalDevVPN.
struct PairingToAppsView: View {
    @ObservedObject private var pairings = PairingStore.shared

    @State private var apps: [DeviceOps.DeviceApp] = []
    @State private var loading = false
    @State private var stage: String?
    @State private var loadError: String?
    @State private var working: String?
    @State private var chosen: DeviceOps.DeviceApp?
    @State private var customTarget: DeviceOps.DeviceApp?
    @State private var customName = "Documents/pairingFile.plist"
    @State private var result: Result?
    @State private var search = ""
    @State private var loaded = false

    struct Result: Identifiable {
        let id = UUID()
        let success: Bool
        let message: String
    }

    var body: some View {
        AuroraScreen {
            Text(pairings.selfPairing.map { "Uses \($0.displayName)'s pairing file. Only sideloaded apps are listed." }
                 ?? "Create this iPhone's pairing file in Tools › Pair first.")
                .font(.footnote)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

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
            } else if loaded && filtered.isEmpty && search.isEmpty {
                GlassCard {
                    Text("No sideloaded apps on this iPhone. Install SideStore, StikDebug or another app with AltLoad first.")
                        .font(.subheadline)
                        .foregroundStyle(Aurora.secondaryText)
                }
            } else if apps.isEmpty {
                GlassActionButton(title: "Load Installed Apps", systemImage: "arrow.clockwise", prominent: true) {
                    Task { await load() }
                }
                .disabled(pairings.selfPairing == nil)
            } else {
                VStack(spacing: 10) {
                    SectionLabel(title: "Sideloaded apps", trailing: "\(filtered.count)")
                    ForEach(filtered) { app in
                        appRow(app)
                    }
                }
            }
        }
        .navigationTitle("Pairing File to Apps")
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
        .confirmationDialog(
            "Put the pairing file in \(chosen?.name ?? "this app")?",
            isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
            titleVisibility: .visible,
            presenting: chosen
        ) { app in
            Button("Place Pairing File") { place(app, as: nil) }
            Button("Other File Name…") { customTarget = app }
            Button("Cancel", role: .cancel) {}
        } message: { app in
            Text(app.bundleID)
        }
        .alert("File name inside the app", isPresented: Binding(get: { customTarget != nil }, set: { if !$0 { customTarget = nil } })) {
            TextField("Documents/pairingFile.plist", text: $customName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Place") {
                if let app = customTarget { place(app, as: customName) }
                customTarget = nil
            }
            Button("Cancel", role: .cancel) { customTarget = nil }
        } message: {
            Text("A path inside the app's container, for example Documents/pairingFile.plist.")
        }
        .alert(item: $result) { result in
            Alert(title: Text(result.success ? "Pairing file placed" : "Couldn't place it"),
                  message: Text(result.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    private var filtered: [DeviceOps.DeviceApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        // Only sideloaded (development-signed) apps: App Store apps can't take the file
        // and have no use for it.
        let sorted = apps.filter(\.debuggable).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }

    private func appRow(_ app: DeviceOps.DeviceApp) -> some View {
        AppBannerRow(
            name: app.name,
            detail: app.bundleID,
            symbol: "hammer.fill"
        ) {
            if working == app.bundleID {
                ProgressRing(value: nil, lineWidth: 3, size: 28, showsPercent: false)
                    .frame(minWidth: 72)
            } else {
                PillButton(title: "Place", tint: Aurora.accent) {
                    chosen = app
                }
                .disabled(working != nil)
            }
        }
    }


    private func load() async {
        loading = true
        loadError = nil
        stage = nil
        defer { loading = false }
        do {
            apps = try await DeviceOps.listApps { text, _ in stage = text }
            loaded = true
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// `path` is a custom file name; nil puts the file wherever the app reads it.
    private func place(_ app: DeviceOps.DeviceApp, as path: String?) {
        guard let pairing = pairings.selfPairing, app.debuggable else { return }
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed?.isEmpty != true else { return }
        working = app.bundleID
        Task {
            defer { working = nil }
            do {
                if let trimmed {
                    try await DeviceOps.placeFile(pairing.fileURL, in: app.bundleID, as: trimmed)
                } else {
                    try await PairingDestination.place(pairing.fileURL, in: app.bundleID)
                }
                result = Result(success: true, message: "\(app.name) now has the pairing file. Reopen the app so it picks the file up.")
            } catch {
                result = Result(success: false, message: error.localizedDescription)
            }
        }
    }
}
