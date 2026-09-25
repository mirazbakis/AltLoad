import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var store = PairingStore.shared
    @StateObject private var install = InstallController.shared
    @State private var showImporter = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                if let app = install.installed {
                    Section("Installed by AltLoad") {
                        HStack(spacing: 14) {
                            icon("square.stack.3d.up.fill", tint: Aurora.violet)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(app.name) \(app.version)").font(.headline)
                                Text(expiryText(app))
                                    .font(.caption)
                                    .foregroundStyle(app.isExpired ? Aurora.danger : .secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .auroraRow()
                }

                Section {
                    if store.items.isEmpty {
                        ContentUnavailableView(
                            "No pairing files yet",
                            systemImage: "tray",
                            description: Text("Pair this iPhone in the Pair tab, or import a pairing file."))
                    } else {
                        ForEach(store.items) { item in
                            row(item)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.delete(item)
                                    }
                                }
                                .contextMenu {
                                    if !item.isAppleTV {
                                        Button("Use for Installs on This iPhone", systemImage: "iphone.gen3") {
                                            store.selfPairingID = item.id
                                        }
                                    }
                                    ShareLink(item: item.fileURL)
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.delete(item)
                                    }
                                }
                        }
                    }
                } header: {
                    Text("Pairing files")
                } footer: {
                    Text("The file marked **This iPhone** is used for installs. Long-press to change it. Files also appear in **Files › On My iPhone › AltLoad**.")
                }
                .auroraRow()
            }
            .auroraListBackground()
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Pairing File", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.propertyList, .xml, .data]) { result in
                switch result {
                case .success(let url):
                    do { _ = try store.importFile(at: url) } catch { importError = error.localizedDescription }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Couldn't import", isPresented: .constant(importError != nil)) {
                Button("OK") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func row(_ item: SavedPairing) -> some View {
        HStack(spacing: 14) {
            icon(item.isAppleTV ? "appletv" : "iphone.gen3", tint: Aurora.indigo)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.headline)
                    if store.selfPairing?.id == item.id {
                        Text("This iPhone")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Aurora.frost)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .glassEffect(.regular.tint(Aurora.violet.opacity(0.5)), in: .capsule)
                    }
                }
                Text([item.model, item.date.formatted(date: .abbreviated, time: .shortened)]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ShareLink(item: item.fileURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Export \(item.displayName) pairing file")
        }
        .padding(.vertical, 4)
    }

    private func icon(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(Aurora.frost)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.tint(tint.opacity(0.45)), in: .circle)
    }

    private func expiryText(_ app: InstalledApp) -> String {
        guard let expiration = app.expiration else { return "Installed \(app.installedAt.formatted(date: .abbreviated, time: .omitted))" }
        return app.isExpired
            ? "Expired \(expiration.formatted(.relative(presentation: .named))). Refresh in the Install tab."
            : "Expires \(expiration.formatted(.relative(presentation: .named)))"
    }
}
