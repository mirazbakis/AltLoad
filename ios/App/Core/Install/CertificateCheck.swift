import AltLoadFFI
import Foundation
import Security

/// Finds apps whose signing certificate is gone, by asking the Apple ID's own
/// developer account which certificates are still active. That's the same Apple
/// service AltLoad signs with, so nothing that allows signing blocks it, and no
/// certificate leaves the iPhone for anyone but Apple.
///
/// An app is signed with one of the certificates in its provisioning profile.
/// When any of them is no longer active, AltLoad signs the app again; the new
/// profile only lists active certificates, so that happens once.
enum CertificateCheck {
    /// The serial numbers of the account's active certificates, normalised, or
    /// nil when the account couldn't be checked. Nothing is shown: a two-factor
    /// prompt ends the check.
    static func activeSerials(for credentials: AppleIDCredentials, anisette: String) async -> Set<String>? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let session = altload_install_session_new() else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { altload_install_session_free(session) }
                let ctx = UnsafeMutableRawPointer(session)
                var out: UnsafeMutablePointer<CChar>?
                let rc = credentials.email.withCString { email in
                    credentials.password.withCString { password in
                        anisette.withCString { servers in
                            #"{"op":"overview"}"#.withCString { request in
                                altload_account_session_run(
                                    session, email, password, servers, request,
                                    nil, declinePromptCallback, ctx, &out)
                            }
                        }
                    }
                }
                let text = out.map { String(cString: $0) } ?? ""
                if let out { altload_string_free(out) }
                guard rc == 0,
                      let overview = try? JSONDecoder().decode(Overview.self, from: Data(text.utf8)) else {
                    continuation.resume(returning: nil)
                    return
                }
                let active = overview.certificates
                    .filter { $0.status.isEmpty || $0.status.caseInsensitiveCompare("Issued") == .orderedSame }
                    .map { normalised($0.serial) }
                continuation.resume(returning: Set(active))
            }
        }
    }

    /// True when the app's profile names a certificate the account no longer has.
    /// False when nothing is known about the app's certificates.
    static func lostCertificate(_ app: InstalledApp, active: Set<String>) -> Bool {
        guard let certificates = app.certificates, !certificates.isEmpty else { return false }
        return certificates.contains { der in
            guard let serial = serial(of: der) else { return false }
            return !active.contains(serial)
        }
    }

    private static func serial(of der: Data) -> String? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let data = SecCertificateCopySerialNumberData(certificate, nil) as Data? else { return nil }
        return normalised(data.map { String(format: "%02X", $0) }.joined())
    }

    /// Hex, upper case, without leading zeros, so both sources compare equal.
    private static func normalised(_ serial: String) -> String {
        let hex = serial.uppercased().filter { $0.isHexDigit }
        let trimmed = hex.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    private struct Overview: Decodable {
        struct Certificate: Decodable {
            let serial: String
            let status: String
        }
        let certificates: [Certificate]
    }
}

/// Nobody is there to answer, so every prompt (two-factor, revoke) is declined.
private let declinePromptCallback: AltLoadPromptCb = { ctx, _, _ in
    guard let ctx else { return }
    _ = "abort".withCString { altload_install_session_respond(OpaquePointer(ctx), $0) }
}
