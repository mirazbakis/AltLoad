import Foundation

/// A release of AltStore, as listed in an AltStore-format source.
struct AltStoreRelease: Codable, Equatable {
    let version: String
    let buildVersion: String?
    let date: String?
    let downloadURL: URL
    let size: Int?
    let minOSVersion: String?
    let notes: String?
    let iconURL: URL?
}

/// Reads the newest AltStore from the official source (https://apps.altstore.io)
/// and caches the IPA in Application Support so refreshes work offline.
enum AltStoreCatalog {
    static let defaultSourceURL = URL(string: "https://apps.altstore.io")!
    static let bundleIdentifier = "com.rileytestut.AltStore"

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

    static func sourceURL() -> URL {
        if let s = UserDefaults.standard.string(forKey: "altstore.sourceURL"),
           let url = URL(string: s), url.scheme == "https" {
            return url
        }
        return defaultSourceURL
    }

    /// Newest AltStore in the configured source. Versions are listed newest first.
    static func latest() async throws -> AltStoreRelease {
        var request = URLRequest(url: sourceURL())
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(http.statusCode)
        }
        let source = try JSONDecoder().decode(Source.self, from: data)
        guard let app = source.apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw CatalogError.notListed
        }
        if let v = app.versions?.first {
            return AltStoreRelease(
                version: v.version, buildVersion: v.buildVersion, date: v.date,
                downloadURL: v.downloadURL, size: v.size, minOSVersion: v.minOSVersion,
                notes: v.localizedDescription, iconURL: app.iconURL)
        }
        if let version = app.version, let url = app.downloadURL {
            return AltStoreRelease(
                version: version, buildVersion: nil, date: app.versionDate,
                downloadURL: url, size: app.size, minOSVersion: nil,
                notes: app.versionDescription, iconURL: app.iconURL)
        }
        throw CatalogError.notListed
    }

    // MARK: - IPA cache

    static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AltStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cachedIPA(version: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent("AltStore-\(version).ipa")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Most recent IPA on disk, used to refresh when offline.
    static func newestCachedIPA() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "ipa" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    static func download(_ release: AltStoreRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if let cached = cachedIPA(version: release.version) { return cached }
        let observer = DownloadProgressObserver(onProgress: progress)
        let (temp, response) = try await URLSession.shared.download(from: release.downloadURL, delegate: observer)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatalogError.http(http.statusCode)
        }
        let destination = cacheDirectory.appendingPathComponent("AltStore-\(release.version).ipa")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
        return destination
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

    enum CatalogError: LocalizedError {
        case http(Int)
        case notListed

        var errorDescription: String? {
            switch self {
            case .http(let code): "The AltStore source returned HTTP \(code)."
            case .notListed: "AltStore isn't listed in the configured source."
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
