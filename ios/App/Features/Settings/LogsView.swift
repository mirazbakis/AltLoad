import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Logs: what AltLoad did, for bug reports. Apple ID emails are masked
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
                    terminal
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

    /// The log as a terminal: oldest at the top, scrolled to the newest line.
    /// Copy and Share include every line; the view shows the last 1000.
    private var terminal: some View {
        let shown = Array(filtered.suffix(1000))
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "$ tail -n \(shown.count) altload.log")
                        .foregroundStyle(Self.promptColor)
                    ForEach(shown) { line in
                        Text(Self.attributed(line))
                            .fixedSize(horizontal: false, vertical: true)
                            .id(line.id)
                    }
                }
                .font(.caption2.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(height: 460)
            .background(Color.black.opacity(0.85), in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Aurora.hairline, lineWidth: 1) }
            .onAppear { if let id = shown.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            .onChange(of: shown.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
        }
    }

    private static let promptColor = Color(red: 0.45, green: 0.95, blue: 0.55)

    /// "HH:mm:ss [category] text", colored like a terminal.
    private static func attributed(_ line: LogLine) -> AttributedString {
        let error = line.level == .error
        // AppLog.timestamp is "yyyy-MM-dd HH:mm:ss.SSS".
        var time = AttributedString(String(AppLog.timestamp(line.date).dropFirst(11).prefix(8)) + " ")
        time.foregroundColor = Color.white.opacity(0.4)
        var tag = AttributedString("[\(line.category.title.lowercased())] ")
        tag.foregroundColor = error ? Aurora.danger : Aurora.sky
        var text = AttributedString(line.text)
        text.foregroundColor = error ? Aurora.danger : Color.white.opacity(0.88)
        return time + tag + text
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
