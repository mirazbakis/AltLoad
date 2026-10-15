import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// .ipa, declared in Info.plist so Files lets it be picked.
    static let ipa = UTType(importedAs: "com.apple.itunes.ipa", conformingTo: .zip)
}

/// The stores AltLoad installs. AltStore is the default.
enum StoreApp: String, CaseIterable, Identifiable, Codable {
    case altstore
    case altstoreBeta
    case sidestore
    case sidestoreNightly
    case sidestoreLC
    case sidestoreLCNightly

    var id: String { rawValue }

    static let defaultsKey = "store.selected"

    /// The store picked on the Install tab. AltStore unless the user changed it.
    static var selected: StoreApp {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(StoreApp.init(rawValue:)) ?? .altstore }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var name: String {
        switch self {
        case .altstore: "AltStore"
        case .altstoreBeta: "AltStore Beta"
        case .sidestore: "SideStore"
        case .sidestoreNightly: "SideStore Nightly"
        case .sidestoreLC: "SideStore + LC"
        case .sidestoreLCNightly: "SideStore + LC Nightly"
        }
    }

    /// Short label under the name on the Install tab.
    var channel: String {
        switch self {
        case .altstore: "Classic"
        case .altstoreBeta: "Beta"
        case .sidestore: "Standalone"
        case .sidestoreLC: "LiveContainer"
        case .sidestoreNightly: "Nightly"
        case .sidestoreLCNightly: "LC Nightly"
        }
    }

    var tagline: String {
        switch self {
        case .altstore: "The original alternative app store"
        case .altstoreBeta: "Early builds of AltStore's next version"
        case .sidestore: "Refreshes apps itself, no AltServer needed"
        case .sidestoreLC: "SideStore inside LiveContainer: run apps without installing them"
        case .sidestoreNightly: "Newest SideStore build from main. Untested"
        case .sidestoreLCNightly: "Newest LiveContainer + SideStore build. Untested"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .altstore: "com.rileytestut.AltStore"
        case .altstoreBeta: "com.rileytestut.AltStore.Beta"
        case .sidestore, .sidestoreNightly: "com.SideStore.SideStore"
        case .sidestoreLC, .sidestoreLCNightly: "com.kdt.livecontainer"
        }
    }

    var isSideStore: Bool { self != .altstore && self != .altstoreBeta }

    /// Nightlies install over the regular build (same bundle ID), so they share
    /// its record and on-device check.
    var isNightly: Bool { self == .sidestoreNightly || self == .sidestoreLCNightly }

    /// The regular store a nightly belongs to; itself otherwise.
    var base: StoreApp {
        switch self {
        case .sidestoreNightly: .sidestore
        case .sidestoreLCNightly: .sidestoreLC
        default: self
        }
    }

    /// The AltStore-format source AltLoad reads first. Settings can override it.
    var defaultSourceURL: URL {
        switch self {
        case .altstore, .altstoreBeta: URL(string: "https://apps.altstore.io")!
        case .sidestore: URL(string: "https://apps.sidestore.io")!
        // LiveContainer has no source of its own; its GitHub releases are the feed.
        case .sidestoreLC: URL(string: "https://api.github.com/repos/LiveContainer/LiveContainer/releases/latest")!
        // Both projects publish nightlies as a GitHub release tagged "nightly".
        case .sidestoreNightly: URL(string: "https://api.github.com/repos/SideStore/SideStore/releases/tags/nightly")!
        case .sidestoreLCNightly: URL(string: "https://api.github.com/repos/LiveContainer/LiveContainer/releases/tags/nightly")!
        }
    }

    /// Where else to look when the source is down, tried in order. SideStore's
    /// repository and source go offline now and then, so it has a mirror, its GitHub
    /// releases and a known-good build to fall back on.
    var fallbackFeeds: [StoreFeed] {
        switch self {
        case .altstore, .altstoreBeta:
            []
        case .sidestore:
            [
                .source(URL(string: "https://sidestore.io/apps.json")!),
                .github(repo: "SideStore/SideStore", asset: "SideStore.ipa"),
                .pinned(version: "0.6.2", url: URL(string: "https://github.com/SideStore/SideStore/releases/download/0.6.2/SideStore.ipa")!)
            ]
        case .sidestoreLC:
            [
                .pinned(version: "3.8.0", url: URL(string: "https://github.com/LiveContainer/LiveContainer/releases/download/3.8.0/LiveContainer%2BSideStore.ipa")!)
            ]
        case .sidestoreNightly:
            [.pinned(version: "Nightly", url: URL(string: "https://github.com/SideStore/SideStore/releases/download/nightly/SideStore.ipa")!)]
        case .sidestoreLCNightly:
            [.pinned(version: "Nightly", url: URL(string: "https://github.com/LiveContainer/LiveContainer/releases/download/nightly/LiveContainer%2BSideStore.ipa")!)]
        }
    }

    /// Shown until the source's icon loads.
    var fallbackSymbol: String {
        switch self {
        case .altstore: "square.stack.3d.up.fill"
        case .altstoreBeta: "testtube.2"
        case .sidestore: "arrow.triangle.2.circlepath"
        case .sidestoreLC: "shippingbox.fill"
        case .sidestoreNightly, .sidestoreLCNightly: "moon.stars.fill"
        }
    }

    /// Icon used when the feed doesn't name one (GitHub releases).
    var defaultIconURL: URL? {
        switch self {
        case .altstore, .altstoreBeta: nil
        default: URL(string: "https://apps.sidestore.io/apps/sidestore/v0.1.1/icon.png")
        }
    }

    /// URL scheme the store registers, to see whether it's on this iPhone.
    var queryScheme: String {
        switch self {
        case .altstore, .altstoreBeta: "altstore-\(bundleIdentifier)"
        case .sidestore, .sidestoreNightly: "sidestore"
        case .sidestoreLC, .sidestoreLCNightly: "livecontainer"
        }
    }

    var sourceDefaultsKey: String { "\(rawValue).sourceURL" }

    /// File-name prefix for cached IPAs. AltStore's are kept as before so old caches are found.
    var cacheName: String {
        switch self {
        case .sidestoreLC: "LiveContainer+SideStore"
        case .sidestoreLCNightly: "LiveContainer+SideStore Nightly"
        default: name
        }
    }

    func sourceURL() -> URL {
        if let s = UserDefaults.standard.string(forKey: sourceDefaultsKey),
           let url = URL(string: s), url.scheme == "https" {
            return url
        }
        return defaultSourceURL
    }

    /// The store an installed bundle ID belongs to. Signing appends the team ID
    /// (com.rileytestut.AltStore.ABCDE12345), so match on the prefix, longest
    /// identifier first so AltStore Beta isn't taken for AltStore.
    static func matching(bundleID: String) -> StoreApp? {
        allCases
            .filter { !$0.isNightly }
            .sorted { $0.bundleIdentifier.count > $1.bundleIdentifier.count }
            .first { bundleID == $0.bundleIdentifier || bundleID.hasPrefix($0.bundleIdentifier + ".") }
    }
}

/// Somewhere a store's newest build can be found.
enum StoreFeed {
    /// An AltStore-format source (apps.json).
    case source(URL)
    /// The latest GitHub release of `repo`, using the asset called `asset`.
    case github(repo: String, asset: String)
    /// A GitHub release by tag (the nightlies), using the asset called `asset`.
    /// Its version is the date the asset was last rebuilt.
    case githubTag(repo: String, tag: String, asset: String)
    /// A fixed build, last resort when everything else is offline.
    case pinned(version: String, url: URL)
}

/// A release of a store app, as listed in an AltStore-format source.
struct StoreRelease: Codable, Equatable {
    let version: String
    let buildVersion: String?
    let date: String?
    let downloadURL: URL
    let size: Int?
    let minOSVersion: String?
    let notes: String?
    let iconURL: URL?
}

/// Reads the newest release from each store's source and caches IPAs in
/// Application Support so refreshes work offline.
enum StoreCatalog {
    private struct Source: Decodable {
        let apps: [App]
    }

    private struct App: Decodable {
        let bundleIdentifier: String
        let iconURL: URL?
        let versions: [Version]?
        // Older sources put the newest version on the app itself.
        let version: String?
        let versionDate: String?
        let downloadURL: URL?
        let size: Int?
        let versionDescription: String?
    }

    private struct Version: Decodable {
        let version: String
        let buildVersion: String?
        let date: String?
        let downloadURL: URL
        let size: Int?
        let minOSVersion: String?
        let localizedDescription: String?
    }

    /// Newest release of `store`: its configured source first, then its fallbacks.
    static func latest(_ store: StoreApp) async throws -> StoreRelease {
        let primary: StoreFeed
        switch store {
        case .sidestoreNightly where store.sourceURL() == store.defaultSourceURL:
            primary = .githubTag(repo: "SideStore/SideStore", tag: "nightly", asset: "SideStore.ipa")
        case .sidestoreLCNightly where store.sourceURL() == store.defaultSourceURL:
            primary = .githubTag(repo: "LiveContainer/LiveContainer", tag: "nightly", asset: "LiveContainer+SideStore.ipa")
        case .sidestoreLC where store.sourceURL() == store.defaultSourceURL:
            primary = .github(repo: "LiveContainer/LiveContainer", asset: "LiveContainer+SideStore.ipa")
        default:
            primary = .source(store.sourceURL())
        }
        var firstError: Error?
        for feed in [primary] + store.fallbackFeeds {
            do {
                return try await release(of: store, from: feed)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if store.isSideStore, firstError != nil { throw CatalogError.repositoryDown(store) }
        throw firstError ?? CatalogError.notListed(store)
    }

    private static func release(of store: StoreApp, from feed: StoreFeed) async throws -> StoreRelease {
        switch feed {
        case .source(let url):
            let data = try await fetch(url, store)
            let source = try JSONDecoder().decode(Source.self, from: data)
            guard let app = source.apps.first(where: { $0.bundleIdentifier == store.bundleIdentifier }) else {
                throw CatalogError.notListed(store)
            }
            if let v = app.versions?.first {
                return StoreRelease(
                    version: v.version, buildVersion: v.buildVersion, date: v.date,
                    downloadURL: v.downloadURL, size: v.size, minOSVersion: v.minOSVersion,
                    notes: v.localizedDescription, iconURL: app.iconURL ?? store.defaultIconURL)
            }
            if let version = app.version, let url = app.downloadURL {
                return StoreRelease(
                    version: version, buildVersion: nil, date: app.versionDate,
                    downloadURL: url, size: app.size, minOSVersion: nil,
                    notes: app.versionDescription, iconURL: app.iconURL ?? store.defaultIconURL)
            }
            throw CatalogError.notListed(store)

        case .github(let repo, let assetName):
            let data = try await fetch(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, store)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let asset = release.assets.first(where: { $0.name == assetName }) else {
                throw CatalogError.notListed(store)
            }
            return StoreRelease(
                version: release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v")),
                buildVersion: nil, date: release.publishedAt,
                downloadURL: asset.browserDownloadURL, size: asset.size, minOSVersion: nil,
                notes: release.body, iconURL: store.defaultIconURL)

        case .githubTag(let repo, let tag, let assetName):
            let data = try await fetch(URL(string: "https://api.github.com/repos/\(repo)/releases/tags/\(tag)")!, store)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard let asset = release.assets.first(where: { $0.name == assetName }) else {
                throw CatalogError.notListed(store)
            }
            let built = asset.updatedAt ?? release.publishedAt
            return StoreRelease(
                version: "Nightly " + String((built ?? "").prefix(10)),
                buildVersion: nil, date: built,
                downloadURL: asset.browserDownloadURL, size: asset.size, minOSVersion: nil,
                notes: release.body, iconURL: store.defaultIconURL)

        case .pinned(let version, let url):
            // Only offer it if the file is actually there.
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "HEAD"
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                throw CatalogError.http(store, http.statusCode)
            }
            return StoreRelease(
                version: version, buildVersion: nil, date: nil, downloadURL: url, size: nil,
                minOSVersion: nil, notes: nil, iconURL: store.defaultIconURL)
        }
    }

    private static func fetch(_ url: URL, _ store: StoreApp) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(store, http.statusCode)
        }
        return data
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int?
            let browserDownloadURL: URL
            let updatedAt: String?
            enum CodingKeys: String, CodingKey {
                case name, size
                case browserDownloadURL = "browser_download_url"
                case updatedAt = "updated_at"
            }
        }
        let tagName: String
        let publishedAt: String?
        let body: String?
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case publishedAt = "published_at"
            case body, assets
        }
    }

    // MARK: - IPA cache

    /// Kept as "AltStore" so IPAs cached by earlier versions are still found.
    static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AltStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileName(_ store: StoreApp, version: String) -> String {
        // Release builds carry "+" or "/" now and then; keep the name file-safe.
        let safe = version.replacingOccurrences(of: "/", with: "-")
        return "\(store.cacheName)-\(safe).ipa"
    }

    static func cachedIPA(_ store: StoreApp, version: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent(fileName(store, version: version))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Most recent IPA of `store` on disk, used to refresh when offline.
    static func newestCachedIPA(_ store: StoreApp) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "ipa" && $0.lastPathComponent.hasPrefix(store.cacheName + "-") }
            .max { a, b in modified(a) < modified(b) }
    }

    static func download(_ store: StoreApp, _ release: StoreRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let cached = cachedIPA(store, version: release.version) { return cached }
        let observer = DownloadProgressObserver(onProgress: progress)
        let (temp, response) = try await URLSession.shared.download(from: release.downloadURL, delegate: observer)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(store, http.statusCode)
        }
        let destination = cacheDirectory.appendingPathComponent(fileName(store, version: release.version))
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        pruneOldIPAs(of: store, keeping: destination)
        return destination
    }

    /// Keeps the newest two IPAs per store so the cache doesn't grow forever.
    private static func pruneOldIPAs(of store: StoreApp, keeping: URL) {
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension == "ipa" && $0.lastPathComponent.hasPrefix(store.cacheName + "-") }
            .sorted { modified($0) > modified($1) }
        for old in files.dropFirst(2) where old != keeping {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Copies an IPA picked in Files into the cache so it can be re-signed later.
    static func importIPA(from url: URL) throws -> URL {
        guard url.pathExtension.lowercased() == "ipa" else { throw CatalogError.notAnIPA }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = cacheDirectory.appendingPathComponent("Imported-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: destination)
        // Coordinate the read so a file still downloading from iCloud Drive arrives whole.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            do { try FileManager.default.copyItem(at: readable, to: destination) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        return destination
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    enum CatalogError: LocalizedError {
        case http(StoreApp, Int)
        case notListed(StoreApp)
        case notAnIPA
        case repositoryDown(StoreApp)

        var errorDescription: String? {
            switch self {
            case .repositoryDown(let store):
                "\(store.name)'s repository is down right now and AltLoad has no copy saved. Try again later, or download the IPA elsewhere and pick it with Install IPA from Files."
            case .notAnIPA: "That file isn't an .ipa."
            case .http(let store, let code): "The \(store.name) source returned HTTP \(code)."
            case .notListed(let store): "\(store.name) isn't listed in the configured source."
            }
        }
    }
}

/// Reports download progress for the async `URLSession.download(from:delegate:)`.
private final class DownloadProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [onProgress] progress, _ in
            onProgress(progress.fractionCompleted)
        }
    }
}
