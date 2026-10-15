import Foundation

/// The cryptex Developer Disk Image iOS 17+ needs for JIT and location simulation.
/// Downloaded once into Application Support; the device personalises and mounts it.
enum DeveloperDiskImage {
    private static let base = "https://github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main/PersonalizedImages/Xcode_iOS_DDI_Cryptex/"

    /// Read by idevice's Cryptex1 loader: the manifest, then the files it names.
    private static let files = [
        "BuildManifest.plist",
        "Image.dmg",
        "Image.dmg.trustcache",
        "Image.dmg.cryptex_info",
        "Image.dmg.root_hash",
    ]

    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeveloperDiskImage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var isDownloaded: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// Downloads whatever is missing and returns the folder.
    static func ensureDownloaded(progress: @escaping @MainActor (String, Double?) -> Void = { _, _ in }) async throws -> URL {
        let dir = directory
        let missing = files.filter { !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        for (index, name) in missing.enumerated() {
            await progress("Downloading the Developer Disk Image (\(index + 1) of \(missing.count))…", nil)
            guard let url = URL(string: base + name) else { continue }
            let (temp, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DDIError.http(name, http.statusCode)
            }
            let destination = dir.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
        }
        return dir
    }

    /// Deletes the downloaded files, e.g. after an iOS update needs a newer image.
    static func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    enum DDIError: LocalizedError {
        case http(String, Int)

        var errorDescription: String? {
            switch self {
            case .http(let name, let code): "Couldn't download \(name) (HTTP \(code))."
            }
        }
    }
}
