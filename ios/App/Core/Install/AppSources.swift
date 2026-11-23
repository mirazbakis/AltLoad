import Foundation

/// An AltStore-format source the user added, and the apps it lists.
struct AppSource: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let iconURL: URL?
    let apps: [SourceApp]

    var id: String { url.absoluteString }
}

/// One app in a source. Versions are newest first.
struct SourceApp: Identifiable, Equatable, Sendable {
    let sourceURL: URL
    let name: String
    let bundleIdentifier: String
    let developer: String?
    let subtitle: String?
    let description: String?
    let iconURL: URL?
    let versions: [SourceVersion]

    var id: String { "\(sourceURL.absoluteString)#\(bundleIdentifier)" }
    var latest: SourceVersion? { versions.first }
}

struct SourceVersion: Identifiable, Equatable, Sendable {
    let version: String
    let date: String?
    let downloadURL: URL
    let size: Int?
    let minOSVersion: String?
    let notes: String?

    var id: String { "\(version)#\(downloadURL.absoluteString)" }
}

/// Sources the user added. Installing one of their apps downloads the IPA into the
/// cache and hands it to the same flow as an IPA from Files, so it refreshes the same way.
@MainActor
final class AppSources: ObservableObject {
    static let shared = AppSources()

    @Published private(set) var sources: [AppSource] = []
    /// Why a saved source couldn't be read, by its URL.
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading = false
    /// The app being downloaded and how far along it is (0…1).
    @Published private(set) var download: (appID: String, fraction: Double)?

    private let urlsKey = "sources.urls"

    /// One tap to add, from the stores AltLoad already knows.
    static let suggestions: [(name: String, url: URL)] = [
        ("AltStore", URL(string: "https://apps.altstore.io")!),
        ("SideStore", URL(string: "https://apps.sidestore.io")!),
        ("Husk", URL(string: "https://raw.githubusercontent.com/Leviidev/Husk/main/altsource.json")!),
    ]

    private init() {}

    var urls: [URL] {
        get { (UserDefaults.standard.stringArray(forKey: urlsKey) ?? []).compactMap(URL.init(string:)) }
        set { UserDefaults.standard.set(newValue.map(\.absoluteString), forKey: urlsKey) }
    }

    func contains(_ url: URL) -> Bool {
        urls.contains { Self.sameSource($0, url) }
    }

    // MARK: - Loading

    /// Reads every saved source again, all at once.
    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let urls = urls
        var loaded: [String: AppSource] = [:]
        var failed: [String: String] = [:]
        await withTaskGroup(of: (URL, Result<AppSource, Error>).self) { group in
            for url in urls {
                group.addTask {
                    do { return (url, .success(try await Self.fetch(url))) } catch { return (url, .failure(error)) }
                }
            }
            for await (url, result) in group {
                switch result {
                case .success(let source): loaded[url.absoluteString] = source
                case .failure(let error): failed[url.absoluteString] = error.localizedDescription
                }
            }
        }
        // Keep the order they were added in.
        sources = urls.compactMap { loaded[$0.absoluteString] }
        errors = failed
        for (url, message) in failed {
            AppLog.shared.error(.install, "Couldn't read source \(url): \(message)")
        }
    }

    /// Checks the link really is a source before saving it.
    func add(_ input: String) async throws {
        guard let url = Self.normalize(input) else { throw SourceError.badLink }
        guard !contains(url) else { throw SourceError.alreadyAdded }
        let source = try await Self.fetch(url)
        urls.append(url)
        sources.append(source)
        errors[url.absoluteString] = nil
        AppLog.shared.info(.install, "Added source \(source.name) (\(source.apps.count) apps)")
    }

    func remove(_ url: URL) {
        urls.removeAll { Self.sameSource($0, url) }
        sources.removeAll { Self.sameSource($0.url, url) }
        errors[url.absoluteString] = nil
    }

    // MARK: - Installed and updates

    /// AltLoad's record of this app, if it signed it. Signing may append the team ID.
    func installed(_ app: SourceApp) -> InstalledApp? {
        InstallController.shared.apps.first {
            $0.bundleID == app.bundleIdentifier || $0.bundleID.hasPrefix(app.bundleIdentifier + ".")
        }
    }

    func hasUpdate(_ app: SourceApp) -> Bool {
        guard let installed = installed(app), let latest = app.latest else { return false }
        return Self.isNewer(latest.version, than: installed.version)
    }

    /// The source app an installed app came from, if any source lists it.
    func sourceApp(for installed: InstalledApp) -> SourceApp? {
        sources.flatMap(\.apps).first {
            installed.bundleID == $0.bundleIdentifier || installed.bundleID.hasPrefix($0.bundleIdentifier + ".")
        }
    }

    var updates: [SourceApp] {
        sources.flatMap(\.apps).filter(hasUpdate)
    }

    // MARK: - Download

    /// Downloads a version's IPA into the cache, named so the install flow shows
    /// "Name version", and returns it for `InstallController.begin(.ipa(_:))`.
    func downloadIPA(_ app: SourceApp, _ version: SourceVersion) async throws -> URL {
        guard download == nil else { throw SourceError.busy }
        download = (app.id, 0)
        defer { download = nil }
        AppLog.shared.info(.install, "Downloading \(app.name) \(version.version) from its source")

        let appID = app.id
        let observer = DownloadProgressObserver { fraction in
            Task { @MainActor in
                if AppSources.shared.download?.appID == appID { AppSources.shared.download = (appID, fraction) }
            }
        }
        let (temp, response) = try await URLSession.shared.download(from: version.downloadURL, delegate: observer)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.http(http.statusCode)
        }
        // A broken link often answers with a web page instead of the IPA.
        guard Self.looksLikeZip(temp) else {
            try? FileManager.default.removeItem(at: temp)
            throw SourceError.notAnIPA
        }

        let base = Self.fileSafe(app.name)
        let destination = StoreCatalog.cacheDirectory
            .appendingPathComponent("Imported-\(base) \(Self.fileSafe(version.version)).ipa")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        // Only the newest download of each app is kept.
        let old = (try? FileManager.default.contentsOfDirectory(at: StoreCatalog.cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in old where file != destination && file.lastPathComponent.hasPrefix("Imported-\(base) ") && file.pathExtension == "ipa" {
            if !InstallController.shared.apps.contains(where: { $0.ipaFile == file.lastPathComponent }) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return destination
    }

    // MARK: - Helpers

    /// Accepts an https link, a link without a scheme, or an altstore:// / sidestore://
    /// "add source" link (`…://source?url=https://…`).
    nonisolated static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "altstore" || scheme == "sidestore" {
            guard let inner = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value else { return nil }
            text = inner
        }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// The same source with or without a trailing slash.
    nonisolated static func sameSource(_ a: URL, _ b: URL) -> Bool {
        func key(_ u: URL) -> String {
            var s = u.absoluteString.lowercased()
            while s.hasSuffix("/") { s.removeLast() }
            return s
        }
        return key(a) == key(b)
    }

    /// Version strings compared number by number; "1.2" and "1.2.0" are the same.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            var p = s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            while p.last == 0 { p.removeLast() }
            return p
        }
        let x = parts(a), y = parts(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    nonisolated static func fetch(_ url: URL) async throws -> AppSource {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.http(http.statusCode)
        }
        return try parse(data, url: url)
    }

    nonisolated static func parse(_ data: Data, url: URL) throws -> AppSource {
        guard let raw = try? JSONDecoder().decode(RawSource.self, from: data) else { throw SourceError.notASource }
        let apps: [SourceApp] = raw.apps.compactMap { item in
            guard let app = item.value, let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
            var versions: [SourceVersion] = (app.versions ?? []).compactMap { item in
                guard let v = item.value, let version = v.version, let link = v.downloadURL.flatMap(URL.init(string:)) else { return nil }
                return SourceVersion(version: version, date: v.date, downloadURL: link, size: v.size?.value,
                                     minOSVersion: v.minOSVersion, notes: v.localizedDescription)
            }
            // Older sources put the only version on the app itself.
            if versions.isEmpty, let version = app.version, let link = app.downloadURL.flatMap(URL.init(string:)) {
                versions = [SourceVersion(version: version, date: app.versionDate, downloadURL: link, size: app.size?.value,
                                          minOSVersion: nil, notes: app.versionDescription)]
            }
            guard !versions.isEmpty else { return nil }
            return SourceApp(sourceURL: url, name: app.name ?? bundleID, bundleIdentifier: bundleID,
                             developer: app.developerName, subtitle: app.subtitle,
                             description: app.localizedDescription,
                             iconURL: app.iconURL.flatMap(URL.init(string:)), versions: versions)
        }
        return AppSource(url: url, name: raw.name ?? url.host ?? url.absoluteString,
                         iconURL: raw.iconURL.flatMap(URL.init(string:)), apps: apps)
    }

    private nonisolated static func looksLikeZip(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2)) == Data("PK".utf8)
    }

    private nonisolated static func fileSafe(_ s: String) -> String {
        String(s.map { "/:\\?%*|\"<>".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
    }

    // Lenient decoding: one malformed app or version doesn't hide the rest.
    private struct RawSource: Decodable {
        let name: String?
        let iconURL: String?
        let apps: [Lenient<RawApp>]
    }

    private struct RawApp: Decodable {
        let name: String?
        let bundleIdentifier: String?
        let developerName: String?
        let subtitle: String?
        let localizedDescription: String?
        let iconURL: String?
        let versions: [Lenient<RawVersion>]?
        let version: String?
        let versionDate: String?
        let versionDescription: String?
        let downloadURL: String?
        let size: Lenient<Int>?
    }

    private struct RawVersion: Decodable {
        let version: String?
        let date: String?
        let downloadURL: String?
        let size: Lenient<Int>?
        let minOSVersion: String?
        let localizedDescription: String?
    }

    private struct Lenient<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    enum SourceError: LocalizedError {
        case badLink, alreadyAdded, notASource, http(Int), notAnIPA, busy

        var errorDescription: String? {
            switch self {
            case .badLink: String(localized: "That isn't a source link. Paste an https link, or an altstore:// or sidestore:// source link.")
            case .alreadyAdded: String(localized: "That source is already added.")
            case .notASource: String(localized: "That link doesn't lead to an AltStore-format source.")
            case .http(let code): String(localized: "The source returned HTTP \(code).")
            case .notAnIPA: String(localized: "The download wasn't an IPA. The source's link may be broken.")
            case .busy: String(localized: "Another download is running.")
            }
        }
    }
}
