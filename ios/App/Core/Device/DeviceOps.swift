import AltLoadFFI
import Foundation

/// Runs one device operation (install an app, manage provisioning profiles,
/// list apps, copy a file into an app) through the LocalDevVPN tunnel, with no
/// Apple ID involved. Backs the on-device AltServer and Tools (Pairing File to Apps,
/// JIT, Location). Operations run one at a time, except a location session, which
/// holds its tunnel open and so runs on its own queue.
enum DeviceOps {
    enum OpError: LocalizedError {
        case noPairing
        case vpnOff
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noPairing: String(localized: "There's no pairing file for this iPhone yet. Create one in Tools › Pair.")
            case .vpnOff: String(localized: "LocalDevVPN is off. Turn it on so AltLoad can reach this iPhone.")
            case .failed(let message): message
            }
        }
    }

    static let queue = DispatchQueue(label: "altload.device-ops", qos: .userInitiated)
    static let longRunningQueue = DispatchQueue(label: "altload.device-ops.long", qos: .userInitiated)

    /// `progress(stage, fraction)`; fraction is nil when indeterminate. Called on the main actor.
    @discardableResult
    static func run(
        _ request: [String: Any],
        on queue: DispatchQueue = DeviceOps.queue,
        progress: @escaping @MainActor (String, Double?) -> Void = { _, _ in }
    ) async throws -> Any {
        let pairingPath: String? = await MainActor.run { PairingStore.shared.selfPairing?.fileURL.path }
        guard let pairingPath else { throw OpError.noPairing }
        guard LocalDevVPN.isActive else { throw OpError.vpnOff }

        let host = LocalDevVPN.targetIP
        let port = LocalDevVPN.remotePairingPort
        // Never take AltLoad's own provisioning profile off the device: AltStore's
        // list of active apps doesn't include it, and AltLoad would stop opening.
        var request = request
        request["protect"] = [Bundle.main.bundleIdentifier].compactMap { $0 }
        let json = String(data: try JSONSerialization.data(withJSONObject: request), encoding: .utf8) ?? "{}"
        let box = ProgressBox(progress)

        let (code, output): (Int32, String) = await withCheckedContinuation { continuation in
            queue.async {
                var owned: [UnsafeMutablePointer<CChar>] = []
                func c(_ s: String) -> UnsafePointer<CChar>? {
                    guard let p = strdup(s) else { return nil }
                    owned.append(p)
                    return UnsafePointer(p)
                }
                var endpoint = AltLoadEndpoint(host: c(host), port: UInt16(clamping: port), identifier: nil, auth_tag: nil)
                var out: UnsafeMutablePointer<CChar>?
                let rc: Int32 = withUnsafePointer(to: &endpoint) { endpointPointer in
                    var config = AltLoadInstallConfig(
                        apple_id: nil, password: nil, anisette_url: nil,
                        pairing_file_path: c(pairingPath),
                        host_name: c("AltLoad"),
                        endpoints: endpointPointer,
                        endpoint_count: 1,
                        ipa_path: nil, device_name: nil, machine_name: nil, server_id: nil,
                        capabilities: nil, extensions_mode: 0)
                    let ctx = Unmanaged.passUnretained(box).toOpaque()
                    return altload_device_run(&config, json, deviceProgressCallback, ctx, &out)
                }
                let text = out.map { String(cString: $0) } ?? ""
                if let out { altload_string_free(out) }
                owned.forEach { free($0) }
                continuation.resume(returning: (rc, text))
            }
        }
        withExtendedLifetime(box) {}

        guard code == 0 else {
            throw OpError.failed(output.isEmpty ? String(localized: "The device operation failed (code \(code)).") : output)
        }
        return (try? JSONSerialization.jsonObject(with: Data(output.utf8), options: [.fragmentsAllowed])) ?? [:]
    }

    // MARK: - Convenience

    struct DeviceApp: Identifiable, Hashable {
        let bundleID: String
        let name: String
        let version: String
        let fileSharing: Bool
        let debuggable: Bool
        var id: String { bundleID }
    }

    static func listApps(progress: @escaping @MainActor (String, Double?) -> Void = { _, _ in }) async throws -> [DeviceApp] {
        let result = try await run(["op": "list_apps"], progress: progress)
        let rows = result as? [[String: Any]] ?? []
        return rows.map {
            DeviceApp(
                bundleID: $0["bundleId"] as? String ?? "",
                name: ($0["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ($0["bundleId"] as? String ?? "App"),
                version: $0["version"] as? String ?? "",
                fileSharing: $0["fileSharing"] as? Bool ?? false,
                debuggable: $0["debuggable"] as? Bool ?? false)
        }
    }

    /// Copies a local file into an installed app's container at `name`
    /// (e.g. "Documents/PairingFile_RemoteRP.plist").
    static func placeFile(_ source: URL, in bundleID: String, as name: String,
                          progress: @escaping @MainActor (String, Double?) -> Void = { _, _ in }) async throws {
        try await run(["op": "place_file", "bundleId": bundleID, "source": source.path, "name": name], progress: progress)
    }
}

extension DeviceOps {
    /// Sets keys in a plist inside an app's container and keeps the rest of it.
    static func mergePreferences(_ values: [String: Any], in bundleID: String, at path: String) async throws {
        try await run(["op": "merge_plist", "bundleId": bundleID, "name": path, "values": values])
    }

    /// This iPhone's UDID, as it reports it over the tunnel.
    static func deviceUDID() async throws -> String {
        let result = try await run(["op": "device_udid"])
        guard let udid = (result as? [String: Any])?["udid"] as? String, !udid.isEmpty else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return udid
    }
}

/// Where each kind of app looks for its pairing file.
enum PairingDestination {
    /// StikDebug and other idevice-based apps use rp_pairing_file.plist.
    static let idevice = "Documents/\(PairingPaths.fileName)"

    /// SideStore's home inside the app's container: the root, or the folder
    /// LiveContainer gives its built-in SideStore. Nil for any other app.
    private static func sideStoreHome(for bundleID: String) -> String? {
        let id = bundleID.lowercased()
        if id.hasPrefix("com.kdt.livecontainer") { return "Documents/SideStore/" }
        if id.hasPrefix("com.mirazbakis.catalyst") || id.hasPrefix("com.sidestore.sidestore") { return "" }
        return nil
    }

    private static func isHusk(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id == "com.husk.app" || id.hasPrefix("com.husk.app.")
    }

    /// AltStore and AltStore Beta, under whatever bundle ID signing gave them.
    private static func isAltStore(_ bundleID: String) -> Bool {
        let store = StoreApp.matching(bundleID: bundleID)
        return store == .altstore || store == .altstoreBeta
    }

    /// AltStore 2.3.1 and later import this file when the user sets up Remote
    /// AltServer, and from then on install and refresh apps without an AltServer.
    static let altStorePath = "Documents/ALTPairingFile.plist"

    static func placesAutomatically(_ bundleID: String) -> Bool {
        sideStoreHome(for: bundleID) != nil || isHusk(bundleID) || isAltStore(bundleID)
    }

    /// Gives an app the pairing file, with the UDID in it, so it doesn't ask on launch.
    /// `stikJIT` is for an app known to keep it where Husk does, whatever its bundle ID.
    static func place(_ pairing: URL, in bundleID: String, stikJIT: Bool = false) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var record = try record(in: Data(contentsOf: pairing))
        if (record["UDID"] as? String)?.isEmpty != false, let udid = try? await DeviceOps.deviceUDID() {
            record["UDID"] = udid
        }
        func put(_ record: [String: Any], as path: String) async throws {
            let file = folder.appendingPathComponent(UUID().uuidString)
            try xml(record).write(to: file)
            try await DeviceOps.placeFile(file, in: bundleID, as: path)
        }

        if isAltStore(bundleID) {
            // AltStore connects with a Remote Pairing record (identifier and keys) and
            // treats a file that also has lockdown keys differently, so it gets only those.
            let remote = record.filter { remoteKeys.contains($0.key) }
            try await put(remote["private_key"] != nil ? remote : record, as: altStorePath)
            return
        }

        guard let home = sideStoreHome(for: bundleID) else {
            try await put(record, as: isHusk(bundleID) || stikJIT ? "Documents/StikJIT/pairingFile.plist" : idevice)
            return
        }

        // Stable builds read this one file, whatever it holds.
        try await put(record, as: home + "Documents/ALTPairingFile.mobiledevicepairing")

        // Newer builds keep one file per protocol and refuse a file with both. They
        // ignore those files until the two settings are saved, as their own import does.
        // Older builds don't need any of this, so it can't fail the placement.
        let lockdown = record.filter { !remoteKeys.contains($0.key) }
        var remote = record.filter { remoteKeys.contains($0.key) }
        remote["UDID"] = record["UDID"]
        let hasLockdown = requiredLockdownKeys.allSatisfy { lockdown[$0] != nil }
        let hasRemote = ["private_key", "public_key", "identifier"].allSatisfy { remote[$0] != nil }
        guard hasLockdown || hasRemote else { return }
        do {
            if hasLockdown { try await put(lockdown, as: home + "Documents/PairingFile_Lockdown.plist") }
            if hasRemote { try await put(remote, as: home + "Documents/PairingFile_RemoteRP.plist") }
            // SideStore's settings file is named after the signed bundle ID, except inside LiveContainer.
            let preferences = home.isEmpty ? "\(bundleID).plist" : "com.SideStore.SideStore.plist"
            try await DeviceOps.mergePreferences(
                ["isPairingReset": false, "activePairingProtocol": hasLockdown ? "lockdown" : "rppairing"],
                in: bundleID, at: home + "Library/Preferences/" + preferences)
        } catch {}
    }

    private static let remoteKeys: Set<String> = ["private_key", "public_key", "identifier", "alt_irk"]
    private static let requiredLockdownKeys = [
        "WiFiMACAddress", "SystemBUID", "RootPrivateKey", "HostPrivateKey", "HostID",
        "RootCertificate", "UDID", "EscrowBag", "HostCertificate", "DeviceCertificate"
    ]

    private static func record(in data: Data) throws -> [String: Any] {
        guard let file = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return file
    }

    /// XML, because SideStore reads the file as a string.
    private static func xml(_ record: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: record, format: .xml, options: 0)
    }
}

private final class ProgressBox: @unchecked Sendable {
    let handler: @MainActor (String, Double?) -> Void
    init(_ handler: @escaping @MainActor (String, Double?) -> Void) { self.handler = handler }
}

private let deviceProgressCallback: AltLoadProgressCb = { ctx, stage, fraction in
    guard let ctx, let stage else { return }
    let box = Unmanaged<ProgressBox>.fromOpaque(ctx).takeUnretainedValue()
    let text = String(cString: stage)
    let value: Double? = fraction < 0 ? nil : fraction
    DispatchQueue.main.async {
        MainActor.assumeIsolated { box.handler(text, value) }
    }
}
