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
        JITCenter.shared.start(bundleID: id, script: JITScripts.shared.script(named: scriptName))
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
    }
}
