import Foundation

/// The machine name AltLoad gives the development certificate it requests. Apple's
/// certificate list shows it, and the core only reuses a certificate whose name
/// matches, so a new name means a new certificate on the next install.
enum CertificateName {
    static let defaultName = "AltLoad"
    static let maxLength = 40
    private static let key = "signing.certificateName"

    static var current: String {
        get { sanitized(UserDefaults.standard.string(forKey: key)) ?? defaultName }
        set {
            let name = sanitized(newValue)
            if name == nil || name == defaultName {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(name, forKey: key)
            }
        }
    }

    /// Trimmed, single-line and at most `maxLength` characters; nil when empty.
    static func sanitized(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        return String(line.prefix(maxLength))
    }

    /// True for a certificate AltLoad requested, under the current or the default name.
    static func isAltLoad(_ machineName: String) -> Bool {
        [current, defaultName].contains { $0.caseInsensitiveCompare(machineName) == .orderedSame }
    }
}
