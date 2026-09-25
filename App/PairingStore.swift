import Foundation

/// A pairing file AltLoad created (or imported) and kept on disk.
struct SavedPairing: Codable, Identifiable, Hashable {
    let name: String
    let model: String
    let udid: String
    /// Folder under Documents/Pairings holding this device's pairing file.
    let folder: String
    let date: Date

    var id: String { folder }
    var displayName: String { name.isEmpty ? "Unknown device" : name }
    var fileURL: URL { PairingPaths.fileURL(inFolder: folder) }
    var isAppleTV: Bool { model.localizedCaseInsensitiveContains("appletv") }
}

enum PairingPaths {
    /// Same name as the upstream tooling so importers recognise it.
    static let fileName = "rp_pairing_file.plist"

    static var rootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairings", isDirectory: true)
    }

    static func fileURL(inFolder folder: String) -> URL {
        rootURL.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Where the Rust side writes before we know which device paired.
    static func temporaryPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("altload-\(UUID().uuidString).plist").path
    }
}

@MainActor
final class PairingStore: ObservableObject {
    static let shared = PairingStore()

    @Published private(set) var items: [SavedPairing] = []

    /// Which pairing file belongs to *this* iPhone (used for installs).
    @Published var selfPairingID: String? = UserDefaults.standard.string(forKey: "selfPairingID") {
        didSet { UserDefaults.standard.set(selfPairingID, forKey: "selfPairingID") }
    }

    private let defaultsKey = "savedPairings.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([SavedPairing].self, from: data) {
            items = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        }
    }

    /// The chosen pairing for this device, else the newest iPhone/iPad one.
    var selfPairing: SavedPairing? {
        if let id = selfPairingID, let match = items.first(where: { $0.id == id }) {
            return match
        }
        return items.first { !$0.isAppleTV }
    }

    /// Moves a freshly written pairing file into its per-device folder and records it.
    func save(fromTemporaryPath tempPath: String, name: String, model: String, udid: String) throws -> SavedPairing {
        let item = try store(fileAt: URL(fileURLWithPath: tempPath), move: true, name: name, model: model, udid: udid)
        // A device paired from its own Settings is this iPhone.
        if !item.isAppleTV { selfPairingID = item.id }
        return item
    }

    /// Adds a pairing file made elsewhere (e.g. by StikPair or on a computer).
    func importFile(at url: URL) throws -> SavedPairing {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let base = url.deletingPathExtension().lastPathComponent
        let name = base == "rp_pairing_file" ? "Imported" : base
        return try store(fileAt: url, move: false, name: name, model: "", udid: "")
    }

    func delete(_ item: SavedPairing) {
        try? FileManager.default.removeItem(at: item.fileURL.deletingLastPathComponent())
        items.removeAll { $0.id == item.id }
        if selfPairingID == item.id { selfPairingID = nil }
        persist()
    }

    private func store(fileAt source: URL, move: Bool, name: String, model: String, udid: String) throws -> SavedPairing {
        let fm = FileManager.default
        let idPart = udid.isEmpty ? UUID().uuidString : udid
        let suffix = String(idPart.filter { $0.isLetter || $0.isNumber }.prefix(6))
        let folder = "\(slug(name.isEmpty ? "Device" : name))-\(suffix)"

        // Drop older entries for the same device (or folder) first.
        for old in items where old.folder == folder || (!udid.isEmpty && old.udid == udid) {
            try? fm.removeItem(at: old.fileURL.deletingLastPathComponent())
        }
        items.removeAll { $0.folder == folder || (!udid.isEmpty && $0.udid == udid) }

        let destination = PairingPaths.fileURL(inFolder: folder)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        if move {
            try fm.moveItem(at: source, to: destination)
        } else {
            try fm.copyItem(at: source, to: destination)
        }

        let item = SavedPairing(name: name, model: model, udid: udid, folder: folder, date: .now)
        items.insert(item, at: 0)
        persist()
        return item
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func slug(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
            } else if out.last != "-" {
                out.append("-")
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "Device" : String(trimmed.prefix(40))
    }
}
