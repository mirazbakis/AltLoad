import AltLoadFFI
import Foundation
import UIKit
import UserNotifications

/// An app AltLoad signed and installed.
/// Where to reach this iPhone's RemotePairing service (via LocalDevVPN).
struct SelfEndpoint: Sendable {
    let host: String
    let port: Int
}

struct InstalledApp: Codable, Equatable {
    let bundleID: String
    let name: String
    let version: String
    let teamID: String
    let expiration: Date?
    let installedAt: Date

    var daysLeft: Int? {
        guard let expiration else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: expiration).day
    }

    var isExpired: Bool { (expiration ?? .distantFuture) < .now }
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

/// Drives the on-device AltStore install: fetch → download → check LocalDevVPN →
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
    @Published private(set) var latest: AltStoreRelease?
    @Published private(set) var catalogError: String?
    @Published private(set) var installed: InstalledApp?
    @Published var twoFactor: TwoFactorPrompt?
    @Published var revoke: RevokePrompt?

    @Published var anisetteURL: String = UserDefaults.standard.string(forKey: "anisette.url") ?? InstallController.defaultAnisette {
        didSet { UserDefaults.standard.set(anisetteURL, forKey: "anisette.url") }
    }

    static let defaultAnisette = "https://ani.sidestore.io"

    private var session: OpaquePointer?
    /// Install parked at `.needsVPN`, with the IPA already downloaded.
    private var pending: (credentials: AppleIDCredentials, ipa: URL)?
    private let installedKey = "installed.altstore"

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .working: true
        default: false
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: installedKey) {
            installed = try? JSONDecoder().decode(InstalledApp.self, from: data)
        }
    }

    /// Stable ID written into AltStore as ALTServerID.
    private static var serverID: String {
        if let id = UserDefaults.standard.string(forKey: "altload.serverID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "altload.serverID")
        return id
    }

    // MARK: - Catalog

    func loadCatalog() async {
        do {
            latest = try await AltStoreCatalog.latest()
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
        }
    }

    var updateAvailable: Bool {
        guard let installed, let latest else { return false }
        return latest.version.compare(installed.version, options: .numeric) == .orderedDescending
    }

    // MARK: - Install

    /// Starts an install or refresh. `ipa` overrides the catalog (e.g. a file the user picked).
    func install(with credentials: AppleIDCredentials, remember: Bool, ipa: URL? = nil) {
        guard !isBusy else { return }
        AppleIDStore.email = credentials.email
        if remember {
            AppleIDStore.savePassword(credentials.password, for: credentials.email)
        } else {
            AppleIDStore.deletePassword(for: credentials.email)
        }
        Task { await run(credentials, ipaOverride: ipa) }
    }

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
        Task { await run(pending.credentials, ipaOverride: pending.ipa, skipVPNCheck: skipCheck) }
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

    private func run(_ credentials: AppleIDCredentials, ipaOverride: URL?, skipVPNCheck: Bool = false) async {
        guard let pairing = PairingStore.shared.selfPairing else {
            phase = .failed("There's no pairing file for this iPhone yet. Create one in the Pair tab first.")
            return
        }

        phase = .checking
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }

        // 1. The IPA.
        let ipa: URL
        if let ipaOverride {
            ipa = ipaOverride
        } else {
            if latest == nil { await loadCatalog() }
            if let release = latest {
                do {
                    ipa = try await AltStoreCatalog.download(release) { [weak self] fraction in
                        Task { @MainActor in self?.phase = .downloading(fraction) }
                    }
                } catch {
                    guard let cached = AltStoreCatalog.newestCachedIPA() else {
                        phase = .failed("Couldn't download AltStore: \(error.localizedDescription)")
                        return
                    }
                    ipa = cached
                }
            } else if let cached = AltStoreCatalog.newestCachedIPA() {
                ipa = cached
            } else {
                phase = .failed(catalogError ?? "Couldn't reach the AltStore source.")
                return
            }
        }

        // 2. LocalDevVPN has to be on so 10.7.0.1 loops back into this iPhone.
        if !skipVPNCheck && !LocalDevVPN.isActive {
            pending = (credentials, ipa)
            phase = .needsVPN
            return
        }
        let endpoints = [SelfEndpoint(host: LocalDevVPN.targetIP, port: LocalDevVPN.remotePairingPort)]

        // 3. Rust does the rest.
        phase = .working("Connecting to this device…", nil)
        let outcome = await runSession(
            credentials: credentials,
            pairingPath: pairing.fileURL.path,
            endpoints: endpoints,
            ipa: ipa)

        switch outcome {
        case .installed(let app):
            installed = app
            if let data = try? JSONEncoder().encode(app) {
                UserDefaults.standard.set(data, forKey: installedKey)
            }
            scheduleExpiryReminder(for: app)
            phase = .success(app)
        case .failed(let message):
            if message == "Cancelled." {
                phase = .idle
            } else if message.localizedCaseInsensitiveContains("anisette") {
                phase = .failed(message + "\n\nThe anisette server may be down. Pick another one in Settings › Anisette server and try again.")
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
        ipa: URL
    ) async -> Outcome {
        guard let session = altload_install_session_new() else {
            return .failed("Couldn't start an install session.")
        }
        self.session = session
        let ctx = Unmanaged.passRetained(self).toOpaque()
        let ctxBits = UInt(bitPattern: ctx)
        let sessionBits = UInt(bitPattern: session)
        let anisette = anisetteURL.isEmpty ? Self.defaultAnisette : anisetteURL
        let serverID = Self.serverID
        let deviceName = UIDevice.current.name

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
                    server_id: c(serverID))

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
                        name: string(result.app_name).isEmpty ? "AltStore" : string(result.app_name),
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

    fileprivate func updateProgress(_ stage: String, _ fraction: Double) {
        guard isBusy else { return }
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

    private func scheduleExpiryReminder(for app: InstalledApp) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["altload.expiry"])
        guard let expiration = app.expiration else { return }
        let fireDate = expiration.addingTimeInterval(-24 * 60 * 60)
        guard fireDate > .now else { return }

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(app.name) expires tomorrow"
            content.body = "Open AltLoad and tap Refresh to keep it working."
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: "altload.expiry",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            center.add(request)
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
