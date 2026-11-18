import AppIntents

/// Shortcuts › AltLoad › Enable JIT: opens an app with AltLoad's debugger, like
/// the JIT tool does.
struct EnableJITIntent: AppIntent {
    static let title: LocalizedStringResource = "Enable JIT"
    static let description = IntentDescription("Opens an app with AltLoad's debugger attached, so it can use JIT. LocalDevVPN has to be on.")
    static let openAppWhenRun = true

    @Parameter(title: "App Bundle ID", description: "For example com.utmapp.UTM")
    var bundleID: String

    @Parameter(title: "Script", description: "A script imported in AltLoad. Leave it empty to use the one the app normally uses.")
    var scriptName: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Enable JIT for \(\.$bundleID)") {
            \.$scriptName
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        AppLog.shared.info(.jit, "Shortcut: Enable JIT for \(id)")
        JITCenter.shared.start(bundleID: id, script: JITScripts.shared.script(named: scriptName))
        return .result()
    }
}

/// An app that can be opened with JIT: pinned, recent, or seen in the last app list.
struct JITAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "App"
    static let defaultQuery = JITAppQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(id)")
    }
}

struct JITAppQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [JITAppEntity] {
        identifiers.map { JITAppEntity(id: $0, name: JITFavorites.shared.name(for: $0)) }
    }

    @MainActor
    func suggestedEntities() async throws -> [JITAppEntity] {
        JITFavorites.shared.suggestions.map { JITAppEntity(id: $0.bundleID, name: $0.name) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [JITAppEntity] {
        JITFavorites.shared.suggestions
            .filter { $0.name.localizedCaseInsensitiveContains(string) || $0.bundleID.localizedCaseInsensitiveContains(string) }
            .map { JITAppEntity(id: $0.bundleID, name: $0.name) }
    }
}

/// Shortcuts › AltLoad › Open App with JIT: like Enable JIT, but picks from the
/// apps AltLoad knows instead of a typed bundle ID.
struct OpenAppWithJITIntent: AppIntent {
    static let title: LocalizedStringResource = "Open App with JIT"
    static let description = IntentDescription("Opens one of your JIT apps with AltLoad's debugger attached. LocalDevVPN has to be on.")
    static let openAppWhenRun = true

    @Parameter(title: "App")
    var app: JITAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$app) with JIT")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppLog.shared.info(.jit, "Shortcut: JIT for \(app.id)")
        JITCenter.shared.start(bundleID: app.id, appName: app.name)
        return .result()
    }
}

struct AltLoadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: EnableJITIntent(),
            phrases: ["Enable JIT with \(.applicationName)"],
            shortTitle: "Enable JIT",
            systemImageName: "bolt.fill")
        AppShortcut(
            intent: OpenAppWithJITIntent(),
            phrases: [
                "Open \(\.$app) with JIT in \(.applicationName)",
                "Enable JIT for \(\.$app) with \(.applicationName)",
            ],
            shortTitle: "Open App with JIT",
            systemImageName: "bolt.circle")
    }
}
