import Foundation
import SwiftUI

/// The stores AltLoad can install. AltStore is the default.
enum StoreApp: String, CaseIterable, Identifiable, Codable {
    case altstore
    case catalyst

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
        case .catalyst: "Catalyst"
        }
    }

    var tagline: String {
        switch self {
        case .altstore: "The original alternative app store"
        case .catalyst: "SideStore fork with Apple ID and Enterprise signing"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .altstore: "com.rileytestut.AltStore"
        case .catalyst: "com.mirazbakis.Catalyst"
        }
    }

    var defaultSourceURL: URL {
        switch self {
        case .altstore: URL(string: "https://apps.altstore.io")!
        case .catalyst: URL(string: "https://raw.githubusercontent.com/mirazbakis/Catalyst/master/source.json")!
        }
    }

    /// Shown until the source's icon loads.
    var fallbackSymbol: String {
        switch self {
        case .altstore: "square.stack.3d.up.fill"
        case .catalyst: "sparkles"
        }
    }

    var sourceDefaultsKey: String { "\(rawValue).sourceURL" }

    func sourceURL() -> URL {
        if let s = UserDefaults.standard.string(forKey: sourceDefaultsKey),
           let url = URL(string: s), url.scheme == "https" {
            return url
        }
        return defaultSourceURL
    }

    /// The store an installed bundle ID belongs to. Signing appends the team ID
    /// (com.rileytestut.AltStore.ABCDE12345), so match on the prefix.
    static func matching(bundleID: String) -> StoreApp? {
        allCases.first { bundleID == $0.bundleIdentifier || bundleID.hasPrefix($0.bundleIdentifier + ".") }
    }
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

    /// Newest release of `store` in its configured source. Versions are listed newest first.
    static func latest(_ store: StoreApp) async throws -> StoreRelease {
        var request = URLRequest(url: store.sourceURL())
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(store, http.statusCode)
        }
        let source = try JSONDecoder().decode(Source.self, from: data)
        guard let app = source.apps.first(where: { $0.bundleIdentifier == store.bundleIdentifier }) else {
            throw CatalogError.notListed(store)
        }
        if let v = app.versions?.first {
            return StoreRelease(
                version: v.version, buildVersion: v.buildVersion, date: v.date,
                downloadURL: v.downloadURL, size: v.size, minOSVersion: v.minOSVersion,
                notes: v.localizedDescription, iconURL: app.iconURL)
        }
        if let version = app.version, let url = app.downloadURL {
            return StoreRelease(
                version: version, buildVersion: nil, date: app.versionDate,
                downloadURL: url, size: app.size, minOSVersion: nil,
                notes: app.versionDescription, iconURL: app.iconURL)
        }
        throw CatalogError.notListed(store)
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
        return "\(store.name)-\(safe).ipa"
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
            .filter { $0.pathExtension == "ipa" && $0.lastPathComponent.hasPrefix(store.name + "-") }
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
            .filter { $0.pathExtension == "ipa" && $0.lastPathComponent.hasPrefix(store.name + "-") }
            .sorted { modified($0) > modified($1) }
        for old in files.dropFirst(2) where old != keeping {
            try? FileManager.default.removeItem(at: old)
        }
    }

    /// Copies a user-picked IPA into the cache so it can be re-signed later.
    static func importIPA(from url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = cacheDirectory.appendingPathComponent("Imported-\(url.lastPathComponent)")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    enum CatalogError: LocalizedError {
        case http(StoreApp, Int)
        case notListed(StoreApp)

        var errorDescription: String? {
            switch self {
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
