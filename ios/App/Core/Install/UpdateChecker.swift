import Foundation

/// Looks for a newer AltLoad on GitHub when the app opens or comes back to the
/// foreground. "Later" hides that version; the next one is announced again.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let downloadPage = URL(string: "https://mirazbakis.github.io/AltLoad/")!
    private static let latestRelease = URL(string: "https://api.github.com/repos/mirazbakis/AltLoad/releases/latest")!
    private static let dismissedKey = "update.dismissedVersion"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    /// The newer version to announce, if there is one.
    @Published private(set) var available: String?
    private var lastCheck: Date?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private struct Release: Decodable {
        let tagName: String
        enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
    }

    func check() async {
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.checkInterval { return }
        lastCheck = .now
        var request = URLRequest(url: Self.latestRelease, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data) else { return }
        let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard latest.compare(currentVersion, options: .numeric) == .orderedDescending,
              latest != UserDefaults.standard.string(forKey: Self.dismissedKey) else { return }
        available = latest
    }

    func dismiss() {
        if let available { UserDefaults.standard.set(available, forKey: Self.dismissedKey) }
        available = nil
    }
}
