import AltLoadFFI
import Foundation
import UIKit
import UserNotifications

/// Where to reach this iPhone's RemotePairing service (via LocalDevVPN).
struct SelfEndpoint: Sendable {
    let host: String
    let port: Int
}

/// What an install flow signs and installs: a store's newest release, or an IPA the user picked.
enum InstallTarget: Identifiable, Equatable {
    case store(StoreApp)
    /// An IPA from Files, already copied into the cache.
    case ipa(URL)

    var id: String {
        switch self {
        case .store(let store): "store.\(store.rawValue)"
        case .ipa(let url): "ipa.\(url.lastPathComponent)"
        }
    }

    var title: String {
        switch self {
        case .store(let store): store.name
        case .ipa(let url):
            url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "Imported-", with: "")
        }
    }

    var store: StoreApp? {
        if case .store(let store) = self { return store }
        return nil
    }
}

/// The stages shown in the install flow's progress bar.
enum InstallStep: Int, CaseIterable, Identifiable, Comparable {
    case download, vpn, signIn, link, sign, install, pairing

    var id: Int { rawValue }

    func title(for target: InstallTarget) -> String {
        switch self {
        case .download: target.store == nil ? "Prepare the IPA" : "Download \(target.title)"
        case .vpn: "Connect to LocalDevVPN"
        case .link: "Open device link"
        case .signIn: "Sign in to Apple"
        case .sign: "Sign the app"
        case .install: "Install the app"
        case .pairing: "Place pairing file"
        }
    }

    var symbol: String {
        switch self {
        case .download: "arrow.down.circle"
        case .vpn: "network.badge.shield.half.filled"
        case .link: "link"
        case .signIn: "person.crop.circle.badge.checkmark"
        case .sign: "signature"
        case .install: "square.and.arrow.down.on.square"
        case .pairing: "doc.badge.gearshape"
        }
    }

    /// Share of the whole bar each step takes.
    var weight: Double {
        switch self {
        case .download: 0.15
        case .vpn: 0.03
        case .link: 0.07
        case .signIn: 0.15
        case .sign: 0.2
        case .install: 0.35
        case .pairing: 0.05
        }
    }

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Whether a store app is on this iPhone, as last checked.
enum DevicePresence: Equatable {
    case unknown
    case checking
    /// `version` is nil when only the URL-scheme check could run.
    case installed(version: String?)
    case missing
}

/// An app AltLoad signed and installed.
struct InstalledApp: Codable, Equatable, Identifiable {
    let bundleID: String
    let name: String
    let version: String
    let teamID: String
    let expiration: Date?
    let installedAt: Date
    /// For IPAs from Files: the file in the IPA cache, used to refresh it later.
    var ipaFile: String? = nil
    /// The store it was installed as, so a nightly refreshes as a nightly.
    var channel: String? = nil

    var id: String { bundleID }

    var store: StoreApp? { StoreApp.matching(bundleID: bundleID) }

    var daysLeft: Int? {
        guard let expiration else { return nil }
        return max(0, Calendar.current.dateComponents([.day], from: .now, to: expiration).day ?? 0)
    }

    var isExpired: Bool { (expiration ?? .distantFuture) < .now }

    /// How to sign this app again.
    var refreshTarget: InstallTarget? {
        if let channel, let chosen = StoreApp(rawValue: channel) { return .store(chosen) }
        if let store { return .store(store) }
        guard let ipaFile else { return nil }
        let url = StoreCatalog.cacheDirectory.appendingPathComponent(ipaFile)
        return FileManager.default.fileExists(atPath: url.path) ? .ipa(url) : nil
    }
}

/// What happens to an app's extensions when it's signed. Same choices as SideStore.
enum ExtensionsMode: Int, CaseIterable, Identifiable {
    /// Each extension gets its own App ID. A free Apple ID only has 10 a week.
    case keep = 0
    /// Extensions are signed with the main app's profile, so only one App ID is used.
    case mainProfile = 1
    /// Extensions are taken out before signing.
    case remove = 2

    var id: Int { rawValue }

    static let defaultsKey = "install.extensionsMode"

    static var saved: ExtensionsMode {
        ExtensionsMode(rawValue: UserDefaults.standard.integer(forKey: defaultsKey)) ?? .keep
    }

    var title: String {
        switch self {
        case .keep: "Keep Extensions"
        case .mainProfile: "Keep, Use Main Profile"
        case .remove: "Remove Extensions"
        }
    }

    var detail: String {
        switch self {
        case .keep: "Widgets and other extensions get their own App IDs."
        case .mainProfile: "Extensions share the app's profile, so only one App ID is used. Some may not run."
        case .remove: "Widgets and other extensions are left out. Saves App IDs."
        }
    }

    var symbol: String {
        switch self {
        case .keep: "puzzlepiece.extension.fill"
        case .mainProfile: "person.crop.rectangle.stack"
        case .remove: "puzzlepiece.extension"
        }
    }
}

struct TwoFactorPrompt: Identifiable, Equatable {
    struct TrustedNumber: Identifiable, Equatable, Decodable {
        let id: Int
        let number: String
    }

    let id = UUID()
    let sms: Bool
    let unknown: Bool
    let lastError: String?
    let numbers: [TrustedNumber]
    let selectedNumberID: Int?
}

struct RevokePrompt: Identifiable, Equatable {
    struct Certificate: Identifiable, Equatable, Decodable {
        let serial: String
        let name: String
        let machine: String
        var id: String { serial }
    }

    let id = UUID()
    let certificates: [Certificate]
}

/// Drives on-device installs: fetch → download → check LocalDevVPN →
/// Rust (tunnel via 10.7.0.1, Apple ID, sign, install) → remember the result.
@MainActor
final class InstallController: ObservableObject {
    static let shared = InstallController()

    enum Phase: Equatable {
        case idle
        case checking
        case downloading(Double)
        /// Waiting for LocalDevVPN to be switched on. The install resumes from here.
        case needsVPN
        case working(String, Double?)
        case success(InstalledApp)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    /// The install flow on screen (full-screen cover), or nil.
    @Published var flow: InstallTarget?
    @Published private(set) var releases: [StoreApp: StoreRelease] = [:]
    @Published private(set) var catalogErrors: [StoreApp: String] = [:]
    /// Everything AltLoad installed, newest first.
    @Published private(set) var apps: [InstalledApp] = []
    @Published var twoFactor: TwoFactorPrompt?
    @Published var revoke: RevokePrompt?
    /// Where the install is, for the progress bar.
    @Published private(set) var step: InstallStep = .download
    /// Progress inside `step`, when known.
    @Published private(set) var stepFraction: Double?
    /// Steps this install goes through. The pairing step is added only when a
    /// SideStore-family IPA turns out to need the pairing file.
    @Published private(set) var steps: [InstallStep] = InstallStep.allCases
    /// Set after installing a SideStore-family app: whether the pairing file went in.
    @Published private(set) var pairingNote: String?
    /// Whether each store is really on this iPhone, from the last device check.
    @Published private(set) var presence: [StoreApp: DevicePresence] = [:]

    @Published var anisetteURL: String = InstallController.savedAnisette {
        didSet { UserDefaults.standard.set(anisetteURL, forKey: "anisette.url") }
    }

    /// AltLoad picks a working server itself unless the user chose one.
    static let defaultAnisette = AnisetteServers.automatic

    /// The saved choice. Anyone still on an old fixed default (SideStore's server, then
    /// jkcoxson's, which stopped answering on its own) moves to Automatic once.
    private static var savedAnisette: String {
        let defaults = UserDefaults.standard
        guard let saved = defaults.string(forKey: "anisette.url") else { return defaultAnisette }
        let oldDefaults = ["https://ani.sidestore.io", "https://ani.jkcoxson.com"]
        if oldDefaults.contains(saved) && !defaults.bool(forKey: "anisette.migrated.auto") {
            defaults.set(true, forKey: "anisette.migrated.auto")
            defaults.set(defaultAnisette, forKey: "anisette.url")
            return defaultAnisette
        }
        return saved
    }

    private var session: OpaquePointer?
    /// Install parked at `.needsVPN`, with the IPA already downloaded.
    private var pending: (credentials: AppleIDCredentials, target: InstallTarget, ipa: URL)?
    private let appsKey = "installed.apps"
    private let legacyInstalledKey = "installed.altstore"

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .working: true
        default: false
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: appsKey),
           let saved = try? JSONDecoder().decode([InstalledApp].self, from: data) {
            apps = saved
        } else if let data = UserDefaults.standard.data(forKey: legacyInstalledKey),
                  let old = try? JSONDecoder().decode(InstalledApp.self, from: data) {
            // AltLoad 1.0 only remembered AltStore.
            apps = [old]
            save()
            UserDefaults.standard.removeObject(forKey: legacyInstalledKey)
        }
    }

    /// Stable ID written into the store app as ALTServerID. AltLoad's AltServer
    /// advertises the same ID, so AltStore treats it as its own server.
    nonisolated static var serverID: String {
        if let id = UserDefaults.standard.string(forKey: "altload.serverID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "altload.serverID")
        return id
    }

    // MARK: - Catalog

    func loadCatalogs() async {
        await withTaskGroup(of: Void.self) { group in
            for store in StoreApp.allCases {
                group.addTask { await self.loadCatalog(store) }
            }
        }
    }

    func loadCatalog(_ store: StoreApp) async {
        do {
            releases[store] = try await StoreCatalog.latest(store)
            catalogErrors[store] = nil
        } catch {
            catalogErrors[store] = error.localizedDescription
        }
    }

    /// AltLoad's own record of installing `store`. It can be stale: the app may have
    /// been deleted since, or installed some other way. See `isOnDevice`.
    func installed(_ store: StoreApp) -> InstalledApp? {
        apps.first { $0.store == store.base }
    }

    /// Whether `store` is on this iPhone: the device check when there is one,
    /// otherwise AltLoad's record.
    func isOnDevice(_ store: StoreApp) -> Bool {
        switch presence[store.base] {
        case .installed: true
        case .missing: false
        default: installed(store) != nil
        }
    }

    /// The version on the device if the check read it, else the recorded one.
    func installedVersion(_ store: StoreApp) -> String? {
        if case .installed(let version) = presence[store.base], let version, !version.isEmpty { return version }
        return installed(store)?.version
    }

    func updateAvailable(_ store: StoreApp) -> Bool {
        // Nightly versions are dates, not comparable with the app's own version.
        guard !store.isNightly else { return false }
        guard isOnDevice(store), let current = installedVersion(store), let latest = releases[store] else { return false }
        return latest.version.compare(current, options: .numeric) == .orderedDescending
    }

    /// Looks for `store` on this iPhone instead of assuming it's there. With a pairing
    /// file and LocalDevVPN on, reads the device's app list (which also gives the
    /// version). Otherwise asks iOS which AltStore URL schemes open.
    func checkDevice(_ requested: StoreApp = .altstore) async {
        guard !isBusy else { return }
        let store = requested.base
        if presence[store] == nil { presence[store] = .checking }

        if PairingStore.shared.selfPairing != nil, LocalDevVPN.isActive,
           let deviceApps = try? await DeviceOps.listApps() {
            if let app = deviceApps.first(where: { StoreApp.matching(bundleID: $0.bundleID) == store }) {
                presence[store] = .installed(version: app.version)
            } else {
                presence[store] = .missing
            }
            return
        }

        // Fall back to the URL schemes each store registers. AltStore's
        // "altstore-<bundle ID>" tells Release and Beta apart. LiveContainer+SideStore
        // also registers "sidestore", so that one can't prove standalone SideStore.
        let app = UIApplication.shared
        func opens(_ scheme: String) -> Bool { URL(string: "\(scheme)://").map(app.canOpenURL) ?? false }
        if opens(store.queryScheme) {
            presence[store] = store == .sidestore && opens(StoreApp.sidestoreLC.queryScheme)
                ? .unknown : .installed(version: nil)
        } else if store.isSideStore || !opens("altstore") {
            presence[store] = .missing
        } else {
            presence[store] = .unknown
        }
    }

    /// Stops listing an app. It stays on the iPhone until the user deletes it there.
    func forget(_ app: InstalledApp) {
        apps.removeAll { $0.bundleID == app.bundleID }
        save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID(app)])
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: appsKey)
        }
    }

    // MARK: - Flow

    /// Opens the full-screen install flow for `target`.
    func begin(_ target: InstallTarget) {
        guard !isBusy else { return }
        pending = nil
        phase = .idle
        pairingNote = nil
        configureSteps(for: target)
        flow = target
    }

    private func configureSteps(for target: InstallTarget) {
        steps = InstallStep.allCases.filter { $0 != .pairing }
        step = .download
        stepFraction = nil
    }

    private func enter(_ newStep: InstallStep, _ fraction: Double? = nil) {
        if newStep == .pairing && !steps.contains(.pairing) { steps.append(.pairing) }
        step = newStep
        stepFraction = fraction
    }

    /// 0…1 across all steps, for the progress bar.
    var overallProgress: Double {
        let total = steps.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return 0 }
        if case .success = phase { return 1 }
        let done = steps.filter { $0 < step }.reduce(0) { $0 + $1.weight }
        return min(1, (done + step.weight * (stepFraction ?? 0)) / total)
    }

    /// Closes the flow. Ignored while an install is running.
    func finish() {
        guard !isBusy else { return }
        pending = nil
        phase = .idle
        flow = nil
    }

    // MARK: - Install

    /// Signs and installs the flow's target with this Apple ID.
    func install(with credentials: AppleIDCredentials, remember: Bool) {
        guard !isBusy, let target = flow else { return }
        AppleIDStore.email = credentials.email
        if remember {
            AppleIDStore.savePassword(credentials.password, for: credentials.email)
        } else {
            AppleIDStore.deletePassword(for: credentials.email)
        }
        Task { await run(credentials, target: target) }
    }

    /// Back to the sign-in step of the current flow.
    func reset() {
        guard !isBusy else { return }
        pending = nil
        phase = .idle
    }

    /// Waits up to ~6 s for the VPN interface to come up (LocalDevVPN hands control
    /// back before the tunnel is fully configured), then resumes.
    func resumeWhenVPNReady() {
        guard case .needsVPN = phase else { return }
        Task {
            for _ in 0..<12 {
                if LocalDevVPN.isActive {
                    resumeAfterVPN()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Continue an install parked at `.needsVPN`, e.g. when LocalDevVPN sends
    /// the user back via `altload://`.
    func resumeAfterVPN(skipCheck: Bool = false) {
        guard case .needsVPN = phase, let pending else { return }
        self.pending = nil
        Task { await run(pending.credentials, target: pending.target, ipaOverride: pending.ipa, skipVPNCheck: skipCheck) }
    }

    func respond(_ response: String) {
        twoFactor = nil
        revoke = nil
        guard let session else { return }
        _ = response.withCString { altload_install_session_respond(session, $0) }
    }

    func cancel() {
        twoFactor = nil
        revoke = nil
        if let session { altload_install_session_cancel(session) }
    }

    private func run(_ credentials: AppleIDCredentials, target: InstallTarget, ipaOverride: URL? = nil, skipVPNCheck: Bool = false) async {
        guard let pairing = PairingStore.shared.selfPairing else {
            phase = .failed("There's no pairing file for this iPhone yet. Create one in Tools › Pair first.")
            return
        }

        phase = .checking
        pairingNote = nil
        enter(.download)
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // 1. The IPA.
        let ipa: URL
        if let ipaOverride {
            ipa = ipaOverride
        } else {
            switch target {
            case .ipa(let url):
                ipa = url
            case .store(let store):
                if releases[store] == nil { await loadCatalog(store) }
                if let release = releases[store] {
                    do {
                        ipa = try await StoreCatalog.download(store, release) { [weak self] fraction in
                            Task { @MainActor in
                                self?.phase = .downloading(fraction)
                                self?.enter(.download, fraction)
                            }
                        }
                    } catch {
                        guard let cached = StoreCatalog.newestCachedIPA(store) else {
                            phase = .failed("Couldn't download \(store.name): \(error.localizedDescription)")
                            return
                        }
                        ipa = cached
                    }
                } else if let cached = StoreCatalog.newestCachedIPA(store) {
                    ipa = cached
                } else {
                    phase = .failed(catalogErrors[store] ?? "Couldn't reach the \(store.name) source.")
                    return
                }
            }
        }

        // 2. LocalDevVPN has to be on so 10.7.0.1 loops back into this iPhone.
        enter(.vpn)
        if !skipVPNCheck && !LocalDevVPN.isActive {
            pending = (credentials, target, ipa)
            phase = .needsVPN
            return
        }
        let endpoints = [SelfEndpoint(host: LocalDevVPN.targetIP, port: LocalDevVPN.remotePairingPort)]

        // 3. Rust does the rest.
        enter(.link)
        phase = .working("Connecting to this device…", nil)
        let outcome = await runSession(
            credentials: credentials,
            pairingPath: pairing.fileURL.path,
            endpoints: endpoints,
            ipa: ipa,
            fallbackName: target.title)

        switch outcome {
        case .installed(var app):
            if case .ipa(let url) = target { app.ipaFile = url.lastPathComponent }
            if case .store(let store) = target { app.channel = store.rawValue }
            // SideStore-family apps need this iPhone's pairing file in their Documents.
            if PairingDestination.isSideStoreFamily(app.bundleID) {
                await placePairingFile(in: app.bundleID, pairing: pairing.fileURL)
            } else if app.store == .sidestoreLC {
                pairingNote = "In LiveContainer, open SideStore and import the pairing file from Files › On My iPhone › AltLoad."
            }
            apps.removeAll { $0.bundleID == app.bundleID }
            apps.insert(app, at: 0)
            save()
            scheduleExpiryReminder(for: app)
            if let store = app.store { presence[store] = .installed(version: app.version) }
            phase = .success(app)
        case .failed(let message):
            if message == "Cancelled." {
                phase = .idle
            } else if message.localizedCaseInsensitiveContains("anisette") || message.contains("-80045") || message.contains("-45061") {
                phase = .failed(message + "\n\nApple refused the sign-in data from the anisette servers AltLoad tried. Open Settings › Anisette, tap Reset Anisette Data, and try again in a few minutes.")
            } else {
                phase = .failed(message)
            }
        }
    }

    private enum Outcome {
        case installed(InstalledApp)
        case failed(String)
    }

    private func runSession(
        credentials: AppleIDCredentials,
        pairingPath: String,
        endpoints: [SelfEndpoint],
        ipa: URL,
        fallbackName: String
    ) async -> Outcome {
        guard let session = altload_install_session_new() else {
            return .failed("Couldn't start an install session.")
        }
        self.session = session
        let ctx = Unmanaged.passRetained(self).toOpaque()
        let ctxBits = UInt(bitPattern: ctx)
        let sessionBits = UInt(bitPattern: session)
        let anisette = await AnisetteServers.shared.signInList(preferred: anisetteURL)
        let serverID = Self.serverID
        let deviceName = UIDevice.current.name
        let capabilities = EntitlementSettings.shared.requestValue
        let extensionsMode = Int32(ExtensionsMode.saved.rawValue)

        let outcome: Outcome = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let session = OpaquePointer(bitPattern: sessionBits) else {
                    continuation.resume(returning: .failed("Invalid session."))
                    return
                }
                var owned: [UnsafeMutablePointer<CChar>] = []
                func c(_ s: String) -> UnsafePointer<CChar>? {
                    guard let p = strdup(s) else { return nil }
                    owned.append(p)
                    return UnsafePointer(p)
                }

                let endpointBuffer = UnsafeMutablePointer<AltLoadEndpoint>.allocate(capacity: max(endpoints.count, 1))
                for (i, e) in endpoints.enumerated() {
                    endpointBuffer[i] = AltLoadEndpoint(
                        host: c(e.host),
                        port: UInt16(clamping: e.port),
                        identifier: nil,
                        auth_tag: nil)
                }

                var config = AltLoadInstallConfig(
                    apple_id: c(credentials.email),
                    password: c(credentials.password),
                    anisette_url: c(anisette),
                    pairing_file_path: c(pairingPath),
                    host_name: c("AltLoad"),
                    endpoints: UnsafePointer(endpointBuffer),
                    endpoint_count: endpoints.count,
                    ipa_path: c(ipa.path),
                    device_name: c(deviceName),
                    machine_name: c("AltLoad"),
                    server_id: c(serverID),
                    capabilities: c(capabilities),
                    extensions_mode: extensionsMode)

                var result = AltLoadInstallResult()
                let rc = altload_install_session_run(
                    session, &config,
                    installProgressCallback, installPromptCallback,
                    UnsafeMutableRawPointer(bitPattern: ctxBits), &result)

                let outcome: Outcome
                if rc == 0 {
                    let expiry = result.expiration_unix > 0
                        ? Date(timeIntervalSince1970: TimeInterval(result.expiration_unix))
                        : Calendar.current.date(byAdding: .day, value: 7, to: .now)
                    outcome = .installed(InstalledApp(
                        bundleID: string(result.bundle_id),
                        name: string(result.app_name).isEmpty ? fallbackName : string(result.app_name),
                        version: string(result.app_version),
                        teamID: string(result.team_id),
                        expiration: expiry,
                        installedAt: .now))
                } else {
                    let message = string(result.error)
                    outcome = .failed(message.isEmpty ? "Install failed (code \(rc))." : message)
                }
                altload_install_result_free(&result)

                // Wipe secrets before freeing.
                for p in owned {
                    memset(p, 0, strlen(p))
                    free(p)
                }
                endpointBuffer.deallocate()
                continuation.resume(returning: outcome)
            }
        }

        altload_install_session_free(session)
        self.session = nil
        Unmanaged<InstallController>.fromOpaque(ctx).release()
        twoFactor = nil
        revoke = nil
        return outcome
    }

    // MARK: - Callbacks from Rust (hopped to main)

    /// Copies the pairing file into a freshly installed SideStore-family app. Not fatal:
    /// the app still works once the file is added from Tools › Pairing File to Apps.
    private func placePairingFile(in bundleID: String, pairing: URL) async {
        enter(.pairing)
        phase = .working("Placing pairing file…", nil)
        do {
            try await DeviceOps.placeFile(pairing, in: bundleID, as: PairingDestination.path(for: bundleID))
            pairingNote = "This iPhone's pairing file is already inside the app."
        } catch {
            pairingNote = "Couldn't place the pairing file (\(error.localizedDescription)). Add it from Tools › Pairing File to Apps."
        }
    }

    fileprivate func updateProgress(_ stage: String, _ fraction: Double) {
        guard isBusy else { return }
        let value: Double? = fraction < 0 ? nil : fraction
        let lower = stage.lowercased()
        if lower.hasPrefix("signing in") || lower.hasPrefix("registering") {
            enter(.signIn, value)
        } else if lower.hasPrefix("signing") || lower.hasPrefix("enabling entitlements")
                    || lower.hasPrefix("preparing altstore") {
            enter(.sign, value)
        } else if lower.hasPrefix("installing") {
            enter(.install, value)
        } else {
            enter(.link, value)
        }
        phase = .working(stage, fraction < 0 ? nil : fraction)
    }

    fileprivate func presentPrompt(kind: Int32, json: Data) {
        switch kind {
        case 1:
            struct Payload: Decodable {
                let unknown: Bool
                let sms: Bool
                let lastError: String?
                let selectedNumberId: Int?
                let numbers: [TwoFactorPrompt.TrustedNumber]
            }
            guard let p = try? JSONDecoder().decode(Payload.self, from: json) else {
                respond("devices")
                return
            }
            twoFactor = TwoFactorPrompt(
                sms: p.sms, unknown: p.unknown, lastError: p.lastError,
                numbers: p.numbers, selectedNumberID: p.selectedNumberId)
        case 2:
            let certs = (try? JSONDecoder().decode([RevokePrompt.Certificate].self, from: json)) ?? []
            revoke = RevokePrompt(certificates: certs)
        default:
            respond("abort")
        }
    }

    // MARK: - Reminder

    private func reminderID(_ app: InstalledApp) -> String {
        "altload.expiry.\(app.store?.rawValue ?? app.bundleID)"
    }

    private func scheduleExpiryReminder(for app: InstalledApp) {
        let center = UNUserNotificationCenter.current()
        // "altload.expiry" was AltLoad 1.0's single AltStore reminder.
        center.removePendingNotificationRequests(withIdentifiers: ["altload.expiry", reminderID(app)])
        guard let expiration = app.expiration else { return }
        let fireDate = expiration.addingTimeInterval(-24 * 60 * 60)
        guard fireDate > .now else { return }

        let identifier = reminderID(app)
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(app.name) expires tomorrow"
            content.body = "Open AltLoad and tap Refresh to keep it working."
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            UNUserNotificationCenter.current().add(request)
        }
    }
}

private let installProgressCallback: AltLoadProgressCb = { ctx, stage, fraction in
    guard let ctx, let stage else { return }
    let controller = Unmanaged<InstallController>.fromOpaque(ctx).takeUnretainedValue()
    let text = String(cString: stage)
    DispatchQueue.main.async {
        controller.updateProgress(text, fraction)
    }
}

private let installPromptCallback: AltLoadPromptCb = { ctx, kind, json in
    guard let ctx, let json else { return }
    let controller = Unmanaged<InstallController>.fromOpaque(ctx).takeUnretainedValue()
    let data = Data(String(cString: json).utf8)
    DispatchQueue.main.async {
        controller.presentPrompt(kind: kind, json: data)
    }
}

private func string(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr else { return "" }
    return String(cString: ptr)
}
