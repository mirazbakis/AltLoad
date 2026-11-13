import Foundation

/// Runs JIT sessions for the JIT tool, the install screen, altload:// links and
/// Shortcuts, one at a time. While a session runs, AltLoad keeps itself awake in
/// the background, since the app it serves is in front.
@MainActor
final class JITCenter: ObservableObject {
    static let shared = JITCenter()

    struct Active: Equatable {
        let appName: String
        let scriptName: String
        var stage: String
        var pid: Int?
    }

    struct Finished: Identifiable {
        let id = UUID()
        let success: Bool
        let title: String
        let message: String
    }

    /// A JIT request from an altload:// link, waiting for the user to allow it.
    struct LinkRequest: Identifiable {
        let id = UUID()
        let bundleID: String?
        let pid: Int?
        /// A saved script the link names.
        let scriptName: String?
        /// A script the link carries itself.
        let scriptSource: String?

        var target: String { bundleID ?? pid.map { String(localized: "process \($0)") } ?? "" }
    }

    @Published private(set) var active: Active?
    @Published var finished: Finished?
    @Published var linkRequest: LinkRequest?
    /// What the last session's script logged, newest last.
    @Published private(set) var log: [String] = []

    private var session: JITSession?
    private let keepAlive = KeepAlive()

    var isRunning: Bool { active != nil }

    /// Starts a session for an app, or for a running process when `pid` is set.
    /// Returns at once; the result arrives in `finished`.
    func start(bundleID: String?, pid: Int? = nil, appName: String? = nil, script: JITScript? = nil) {
        let name = appName ?? bundleID ?? pid.map { String(localized: "process \($0)") } ?? ""
        guard bundleID?.isEmpty == false || pid != nil else {
            finished = Finished(success: false, title: String(localized: "Couldn't enable JIT"),
                                message: String(localized: "Name an app to open with JIT."))
            return
        }
        if let active {
            finished = Finished(success: false, title: String(localized: "JIT is already running"),
                                message: String(localized: "AltLoad is still with \(active.appName). Stop that session in Tools › JIT first."))
            return
        }
        let script = script ?? bundleID.map { JITScripts.shared.script(for: $0) } ?? JITScripts.shared.builtIn
        let session = JITSession()
        self.session = session
        log = []
        active = Active(appName: name, scriptName: script.name, stage: String(localized: "Starting…"))
        keepAlive.startAudio()

        Task {
            defer {
                keepAlive.stopAudio()
                self.session = nil
                active = nil
            }
            do {
                let target = try await Self.target { text, _ in self.active?.stage = text }
                let outcome = try await session.run(bundleID: bundleID, pid: pid, script: script, target: target) { event in
                    Task { @MainActor in JITCenter.shared.handle(event) }
                }
                finished = Self.summary(outcome, appName: name, scriptName: script.name)
            } catch is CancellationError {
                finished = Finished(success: true, title: String(localized: "JIT stopped"),
                                    message: String(localized: "Stopped before AltLoad reached \(name)."))
            } catch {
                finished = Finished(success: false, title: String(localized: "Couldn't enable JIT"),
                                    message: error.localizedDescription)
            }
        }
    }

    /// Lets the app go and ends the session.
    func stop() {
        session?.stop()
    }

    private func handle(_ event: JITSession.Event) {
        switch event {
        case .stage(let text):
            active?.stage = text
        case .attached(let pid):
            active?.pid = pid
            active?.stage = String(localized: "Serving JIT requests")
        case .log(let line):
            log.append(line)
            if log.count > 200 { log.removeFirst(log.count - 200) }
        }
    }

    // MARK: - Links

    /// Takes altload://enable-jit?bundle-id=…[&pid=…][&script-name=…][&script-data=<base64>].
    /// Returns false for any other link.
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "altload" else { return false }
        let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
        guard action == "enable-jit" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        let script = value("script-data").flatMap(Self.decodeBase64)
        linkRequest = LinkRequest(
            bundleID: value("bundle-id") ?? value("bundleid"),
            pid: value("pid").flatMap(Int.init),
            scriptName: value("script-name"),
            scriptSource: script)
        return true
    }

    func allow(_ request: LinkRequest) {
        linkRequest = nil
        var script: JITScript?
        if let source = request.scriptSource {
            script = JITScript(name: String(localized: "Script from link"), source: source, builtIn: false)
        } else if let name = request.scriptName {
            guard let saved = JITScripts.shared.script(named: name) else {
                finished = Finished(success: false, title: String(localized: "Couldn't enable JIT"),
                                    message: String(localized: "The link asks for the script \"\(name)\", which isn't in AltLoad. Import it in Tools › JIT › Scripts."))
                return
            }
            script = saved
        }
        start(bundleID: request.bundleID, pid: request.pid, script: script)
    }

    private static func decodeBase64(_ text: String) -> String? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        return Data(base64Encoded: base).flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: - Helpers

    private static func target(progress: @escaping @MainActor (String, Double?) -> Void) async throws -> JITSession.Target {
        guard let pairing = PairingStore.shared.selfPairing else { throw DeviceOps.OpError.noPairing }
        guard LocalDevVPN.isActive else { throw DeviceOps.OpError.vpnOff }
        let ddi = try await DeveloperDiskImage.ensureDownloaded(progress: progress)
        return JITSession.Target(
            pairingPath: pairing.fileURL.path,
            host: LocalDevVPN.targetIP,
            port: LocalDevVPN.remotePairingPort,
            ddiDirectory: ddi.path)
    }

    private static func summary(_ outcome: JITSession.Outcome, appName: String, scriptName: String) -> Finished {
        let title = String(localized: "JIT enabled")
        switch outcome.ended {
        case "app", "quiet":
            let message = outcome.requests > 0
                ? String(localized: "\(appName) has JIT. AltLoad prepared its JIT memory \(outcome.requests) times, then let go.")
                : String(localized: "\(appName) has JIT. AltLoad let go when it was done.")
            return Finished(success: true, title: title, message: message)
        case "attach":
            return Finished(success: true, title: title, message: String(localized: "\(appName) has JIT until you close it."))
        case "exited":
            return Finished(success: true, title: String(localized: "JIT session ended"), message: String(localized: "\(appName) closed. Open it with JIT again next time."))
        case "stopped":
            return Finished(success: true, title: String(localized: "JIT stopped"), message: String(localized: "AltLoad let go of \(appName)."))
        default:
            return Finished(success: true, title: title, message: String(localized: "The script \(scriptName) finished for \(appName)."))
        }
    }
}
