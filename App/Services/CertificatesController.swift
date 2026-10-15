import AltLoadFFI
import Foundation

/// A development certificate on the signed-in Apple ID's own team.
struct DevCertificate: Identifiable, Hashable, Decodable {
    let serial: String
    let certificateId: String
    let name: String
    let machineName: String
    let machineId: String
    let platform: String
    let type: String
    let maxActive: Int
    let status: String
    let expires: Int64

    var id: String { serial.isEmpty ? certificateId : serial }
    var expiration: Date? { expires > 0 ? Date(timeIntervalSince1970: TimeInterval(expires)) : nil }
    var isExpired: Bool { (expiration ?? .distantFuture) < .now }
    /// Made by AltLoad itself (isideload names the machine after the app).
    var isAltLoad: Bool { machineName.caseInsensitiveCompare("AltLoad") == .orderedSame }
    var displayName: String { machineName.isEmpty ? (name.isEmpty ? "Unnamed certificate" : name) : machineName }
}

struct DevAppID: Identifiable, Hashable, Decodable {
    let id: String
    let identifier: String
    let name: String
    let expires: Int64
    var expiration: Date? { expires > 0 ? Date(timeIntervalSince1970: TimeInterval(expires)) : nil }
}

struct DevDevice: Identifiable, Hashable, Decodable {
    let name: String
    let udid: String
    let status: String
    var id: String { udid }
}

struct AccountOverview: Decodable, Equatable {
    struct Team: Decodable, Equatable {
        let id: String
        let name: String
    }
    struct AppIDs: Decodable, Equatable {
        let items: [DevAppID]?
        let max: Int?
        let available: Int?
        let error: String?
    }

    let team: Team
    let certificates: [DevCertificate]
    let appIds: AppIDs
    let devices: [DevDevice]

    var certificateLimit: Int? { certificates.map(\.maxActive).max().flatMap { $0 > 0 ? $0 : nil } }
}

/// Lists and revokes the development certificates of the user's own Apple ID,
/// and shows the App IDs and devices on the team. Uses the same Rust session
/// (and 2FA prompts) as installs.
@MainActor
final class CertificatesController: ObservableObject {
    static let shared = CertificatesController()

    enum Phase: Equatable {
        case signedOut
        case loading(String)
        case loaded
        case failed(String)
    }

    @Published var phase: Phase = .signedOut
    @Published private(set) var overview: AccountOverview?
    @Published private(set) var lastUpdated: Date?
    @Published var twoFactor: TwoFactorPrompt?

    private var session: OpaquePointer?
    private var credentials: AppleIDCredentials?

    var isBusy: Bool {
        if case .loading = phase { return true }
        return false
    }

    private init() {}

    /// Uses the remembered password if there is one; otherwise the caller shows the sign-in sheet.
    var savedCredentials: AppleIDCredentials? {
        let email = AppleIDStore.email
        guard !email.isEmpty, let password = AppleIDStore.password(for: email) else { return nil }
        return AppleIDCredentials(email: email, password: password)
    }

    func load(with credentials: AppleIDCredentials, remember: Bool? = nil) {
        if let remember {
            AppleIDStore.email = credentials.email
            if remember {
                AppleIDStore.savePassword(credentials.password, for: credentials.email)
            } else {
                AppleIDStore.deletePassword(for: credentials.email)
            }
        }
        self.credentials = credentials
        run(request: ["op": "overview"])
    }

    func refresh() {
        guard credentials != nil else { return }
        run(request: ["op": "overview"])
    }

    func revoke(_ certificates: [DevCertificate]) {
        let serials = certificates.map(\.serial).filter { !$0.isEmpty }
        guard !serials.isEmpty else { return }
        run(request: ["op": "revoke", "serials": serials])
    }

    func signOut() {
        credentials = nil
        overview = nil
        lastUpdated = nil
        phase = .signedOut
    }

    func respond(_ response: String) {
        twoFactor = nil
        guard let session else { return }
        _ = response.withCString { altload_install_session_respond(session, $0) }
    }

    func cancel() {
        twoFactor = nil
        if let session { altload_install_session_cancel(session) }
    }

    // MARK: - Rust bridge

    private func run(request: [String: Any]) {
        guard !isBusy, let credentials else { return }
        guard let requestData = try? JSONSerialization.data(withJSONObject: request),
              let requestJSON = String(data: requestData, encoding: .utf8),
              let session = altload_install_session_new() else {
            phase = .failed("Couldn't start a session.")
            return
        }
        self.session = session
        phase = .loading((request["op"] as? String) == "revoke" ? "Revoking certificate…" : "Signing in to Apple…")

        let anisette = InstallController.shared.anisetteURL.isEmpty
            ? InstallController.defaultAnisette
            : InstallController.shared.anisetteURL
        let ctx = Unmanaged.passRetained(self).toOpaque()
        let ctxBits = UInt(bitPattern: ctx)
        let sessionBits = UInt(bitPattern: session)

        Task {
            let result: Result<Data, AccountError> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let session = OpaquePointer(bitPattern: sessionBits) else {
                        continuation.resume(returning: .failure(.message("Invalid session.")))
                        return
                    }
                    var out: UnsafeMutablePointer<CChar>?
                    let rc = credentials.email.withCString { emailC in
                        credentials.password.withCString { passC in
                            anisette.withCString { aniC in
                                requestJSON.withCString { reqC in
                                    altload_account_session_run(
                                        session, emailC, passC, aniC, reqC,
                                        accountProgressCallback, accountPromptCallback,
                                        UnsafeMutableRawPointer(bitPattern: ctxBits), &out)
                                }
                            }
                        }
                    }
                    let text = out.map { String(cString: $0) } ?? ""
                    if let out { altload_string_free(out) }
                    continuation.resume(returning: rc == 0
                        ? .success(Data(text.utf8))
                        : .failure(.message(text.isEmpty ? "Request failed (code \(rc))." : text)))
                }
            }

            altload_install_session_free(session)
            self.session = nil
            Unmanaged<CertificatesController>.fromOpaque(ctx).release()
            twoFactor = nil

            switch result {
            case .success(let data):
                do {
                    overview = try JSONDecoder().decode(AccountOverview.self, from: data)
                    lastUpdated = .now
                    phase = .loaded
                } catch {
                    phase = .failed("Couldn't read the account data: \(error.localizedDescription)")
                }
            case .failure(.message(let message)):
                if message == "Cancelled." {
                    phase = overview == nil ? .signedOut : .loaded
                } else {
                    phase = .failed(message)
                    if message.localizedCaseInsensitiveContains("sign-in failed") { self.credentials = nil }
                }
            }
        }
    }

    private enum AccountError: Error { case message(String) }

    fileprivate func updateProgress(_ stage: String) {
        guard isBusy else { return }
        phase = .loading(stage)
    }

    fileprivate func presentTwoFactor(_ json: Data) {
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
    }
}

private let accountProgressCallback: AltLoadProgressCb = { ctx, stage, _ in
    guard let ctx, let stage else { return }
    let controller = Unmanaged<CertificatesController>.fromOpaque(ctx).takeUnretainedValue()
    let text = String(cString: stage)
    DispatchQueue.main.async { controller.updateProgress(text) }
}

private let accountPromptCallback: AltLoadPromptCb = { ctx, kind, json in
    guard let ctx, let json else { return }
    let controller = Unmanaged<CertificatesController>.fromOpaque(ctx).takeUnretainedValue()
    let data = Data(String(cString: json).utf8)
    DispatchQueue.main.async {
        if kind == 1 {
            controller.presentTwoFactor(data)
        } else {
            controller.respond("abort")
        }
    }
}
