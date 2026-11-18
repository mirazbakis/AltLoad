import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Tools › Logs: what AltLoad did, for bug reports. Apple ID emails are masked
/// and passwords, codes, tokens and pairing files are never written.
struct LogsView: View {
    @State private var lines: [LogLine] = []
    @State private var category: LogCategory?
    @State private var search = ""
    @State private var errorsOnly = false
    @State private var copied = false
    @State private var confirmClear = false

    var body: some View {
        AuroraScreen {
            Text("AltLoad keeps its last 3000 log lines on this iPhone. Share them when you report a problem. Apple ID emails are masked, and passwords, codes, tokens and pairing files are never logged.")
                .font(.footnote)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            filters

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = AppLog.deviceSummary + "\n\n" + AppLog.shared.text(filtered)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? String(localized: "Copied") : String(localized: "Copy"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AltLoadButtonStyle(prominent: false))

                ShareLink(item: LogExport(lines: filtered), preview: SharePreview(String(localized: "AltLoad log"))) {
                    Label(String(localized: "Share"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AltLoadButtonStyle(prominent: true))
            }
            .disabled(filtered.isEmpty)

            VStack(spacing: 10) {
                SectionLabel(title: "Log", trailing: "\(filtered.count)")
                if filtered.isEmpty {
                    GlassCard {
                        Text(lines.isEmpty ? String(localized: "Nothing logged yet.") : String(localized: "No lines match."))
                            .font(.subheadline)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Newest first. Copy and Share include every line.
                        ForEach(filtered.suffix(1000).reversed()) { line in
                            row(line)
                            Divider().overlay(Aurora.hairline)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .cardSurface()
                }
            }

            Button(role: .destructive) {
                confirmClear = true
            } label: {
                Label(String(localized: "Clear Log"), systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(AltLoadButtonStyle(prominent: false, tint: Aurora.danger))
            .disabled(lines.isEmpty)
        }
        .navigationTitle(String(localized: "Logs"))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: String(localized: "Search the log"))
        .confirmationDialog(String(localized: "Clear the log?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(String(localized: "Clear Log"), role: .destructive) { AppLog.shared.clear() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: AppLog.didChange)) { _ in reload() }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(String(localized: "All"), selected: category == nil) { category = nil }
                    ForEach(LogCategory.allCases) { item in
                        chip(item.title, selected: category == item) { category = item }
                    }
                }
                .padding(.horizontal, 4)
            }
            Toggle(String(localized: "Errors only"), isOn: $errorsOnly)
                .font(.footnote)
                .padding(.horizontal, 4)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Aurora.frost)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background((selected ? Aurora.accent : Aurora.raised).opacity(selected ? 0.5 : 1), in: .capsule)
                .overlay { Capsule().strokeBorder(selected ? Aurora.accent : Aurora.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func row(_ line: LogLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(AppLog.timestamp(line.date))
                Text(line.category.title)
                    .foregroundStyle(line.level == .error ? Aurora.danger : Aurora.sky)
            }
            .font(.caption2.monospaced())
            .foregroundStyle(Aurora.secondaryText)
            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(line.level == .error ? Aurora.danger : Aurora.frost)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var filtered: [LogLine] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return lines.filter { line in
            (category == nil || line.category == category)
                && (!errorsOnly || line.level == .error)
                && (query.isEmpty || line.text.localizedCaseInsensitiveContains(query))
        }
    }

    private func reload() {
        lines = AppLog.shared.snapshot()
    }
}

/// The log as a .txt file for ShareLink, written only when it's shared.
struct LogExport: Transferable {
    let lines: [LogLine]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            SentTransferredFile(AppLog.shared.exportFile(export.lines))
        }
    }
}

#Preview {
    NavigationStack { LogsView() }
        .auroraTheme()
}
