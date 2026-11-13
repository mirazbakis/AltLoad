import Foundation
import Security

/// Apple IDs in UserDefaults; passwords (only if the user opts in) in the Keychain,
/// readable only while this device is unlocked and never synced. Several Apple IDs
/// can be saved; `email` is the one used by default.
enum AppleIDStore {
    private static let emailKey = "appleID.email"
    private static let accountsKey = "appleID.accounts"
    private static let service = "AltLoad.AppleID"

    /// The Apple ID used by default. Setting it also saves it to `accounts`.
    static var email: String {
        get { UserDefaults.standard.string(forKey: emailKey) ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: emailKey)
            if !newValue.isEmpty, !accounts.contains(where: { $0.caseInsensitiveCompare(newValue) == .orderedSame }) {
                UserDefaults.standard.set(accounts + [newValue], forKey: accountsKey)
            }
        }
    }

    /// Every saved Apple ID, in the order they were added. Includes the one saved
    /// before several were possible.
    static var accounts: [String] {
        var list = UserDefaults.standard.stringArray(forKey: accountsKey) ?? []
        let current = email
        if !current.isEmpty, !list.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            list.insert(current, at: 0)
        }
        return list
    }

    /// Forgets one Apple ID and its password. If it was the default, the next one takes over.
    static func remove(_ account: String) {
        deletePassword(for: account)
        let rest = accounts.filter { $0.caseInsensitiveCompare(account) != .orderedSame }
        UserDefaults.standard.set(rest, forKey: accountsKey)
        if email.caseInsensitiveCompare(account) == .orderedSame {
            UserDefaults.standard.set(rest.first ?? "", forKey: emailKey)
            forgetSession()
        }
    }

    static func password(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func savePassword(_ password: String, for email: String) {
        deletePassword(for: email)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func deletePassword(for email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func forgetAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: accountsKey)
        forgetSession()
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.removeItem(at: support.appendingPathComponent("AltLoad/signin", isDirectory: true))
        }
    }

    /// Deletes the saved password once Apple has locked the account, so it can't be
    /// sent again. A plain refusal keeps it, since Apple gives the same answer for
    /// anisette data it won't accept. The wording comes from sign_in.rs in the Rust core.
    static func forgetPasswordIfRejected(message: String, email: String) {
        if message.contains("Apple ID is locked") {
            deletePassword(for: email)
        }
    }

    /// Removes the developer session the Rust core saves after a sign-in, so the
    /// next install or account request has to sign in again.
    static func forgetSession() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: support.appendingPathComponent("AltLoad/session", isDirectory: true))
    }
}

struct AppleIDCredentials {
    let email: String
    let password: String
}
