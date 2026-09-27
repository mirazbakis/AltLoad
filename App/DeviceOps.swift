import AltLoadFFI
import Foundation

/// Runs one device operation (install an app, manage provisioning profiles,
/// list apps, copy a file into an app) through the LocalDevVPN tunnel, with no
/// Apple ID involved. Backs the on-device AltServer and Tools › Pairing File to Apps.
/// Operations run one at a time.
enum DeviceOps {
    enum OpError: LocalizedError {
        case noPairing
        case vpnOff
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noPairing: "There's no pairing file for this iPhone yet. Create one in Tools › Pair."
            case .vpnOff: "LocalDevVPN is off. Turn it on so AltLoad can reach this iPhone."
            case .failed(let message): message
            }
        }
    }

    private static let queue = DispatchQueue(label: "altload.device-ops", qos: .userInitiated)

    /// `progress(stage, fraction)`; fraction is nil when indeterminate. Called on the main actor.
    @discardableResult
    static func run(
        _ request: [String: Any],
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
                        ipa_path: nil, device_name: nil, machine_name: nil, server_id: nil)
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
            throw OpError.failed(output.isEmpty ? "The device operation failed (code \(code))." : output)
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

/// Where each kind of app looks for its pairing file.
enum PairingDestination {
    /// Catalyst and SideStore read Documents/PairingFile_RemoteRP.plist.
    static let sideStoreName = "Documents/PairingFile_RemoteRP.plist"
    /// StikDebug and other idevice-based apps use rp_pairing_file.plist.
    static let idevice = "Documents/\(PairingPaths.fileName)"

    static func path(for bundleID: String) -> String {
        let id = bundleID.lowercased()
        if id.hasPrefix("com.mirazbakis.catalyst") || id.hasPrefix("com.sidestore.sidestore") {
            return sideStoreName
        }
        return idevice
    }

    static func isSideStoreFamily(_ bundleID: String) -> Bool {
        path(for: bundleID) == sideStoreName
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
