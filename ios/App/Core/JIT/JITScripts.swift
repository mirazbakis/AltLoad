import Foundation

/// A script that drives a JIT session: AltLoad's own, or one the user imported.
struct JITScript: Identifiable, Hashable {
    let name: String
    let source: String
    let builtIn: Bool
    var id: String { name }
}

/// AltLoad's JIT script, the scripts imported into Application Support/AltLoad/JIT
/// Scripts, and which script each app uses.
@MainActor
final class JITScripts: ObservableObject {
    static let shared = JITScripts()
    static let builtInName = "AltLoad"
    private static let assignmentsKey = "jit.scriptForApp"

    enum ImportError: LocalizedError {
        case unreadable
        case empty

        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "That file couldn't be read as text.")
            case .empty: String(localized: "That script is empty.")
            }
        }
    }

    let builtIn: JITScript = {
        let url = Bundle.main.url(forResource: "altload-jit", withExtension: "js")
        let source = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return JITScript(name: JITScripts.builtInName, source: source, builtIn: true)
    }()

    @Published private(set) var imported: [JITScript] = []
    @Published private(set) var assignments: [String: String] =
        UserDefaults.standard.dictionary(forKey: assignmentsKey) as? [String: String] ?? [:]

    var all: [JITScript] { [builtIn] + imported }

    private var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("AltLoad/JIT Scripts", isDirectory: true)
    }

    private init() { reload() }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        imported = files
            .filter { $0.pathExtension.lowercased() == "js" }
            .compactMap { url in
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return JITScript(name: url.deletingPathExtension().lastPathComponent, source: source, builtIn: false)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func script(named name: String?) -> JITScript? {
        guard let name, !name.isEmpty else { return nil }
        return all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The script `bundleID` uses: the one picked for it, else AltLoad's.
    func script(for bundleID: String) -> JITScript {
        script(named: assignments[bundleID]) ?? builtIn
    }

    /// Picks the script `bundleID` uses; nil (or AltLoad's) for AltLoad's own.
    func assign(_ name: String?, to bundleID: String) {
        if let name, name != Self.builtInName {
            assignments[bundleID] = name
        } else {
            assignments.removeValue(forKey: bundleID)
        }
        UserDefaults.standard.set(assignments, forKey: Self.assignmentsKey)
    }

    /// Apps that use `script`.
    func apps(using script: JITScript) -> [String] {
        assignments.filter { $0.value == script.name }.map(\.key).sorted()
    }

    /// Copies a .js file in, under its own name (with a number added if taken).
    @discardableResult
    func importScript(from url: URL) throws -> JITScript {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { throw ImportError.unreadable }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty }

        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        var name = base.isEmpty ? "Script" : base
        var n = 2
        while script(named: name) != nil {
            name = "\(base) \(n)"
            n += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try source.write(to: folder.appendingPathComponent("\(name).js"), atomically: true, encoding: .utf8)
        reload()
        return script(named: name) ?? JITScript(name: name, source: source, builtIn: false)
    }

    func delete(_ script: JITScript) {
        guard !script.builtIn else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(script.name).js"))
        for app in apps(using: script) { assign(nil, to: app) }
        reload()
    }
}
