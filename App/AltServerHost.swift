import CryptoKit
import Foundation
import Network
import UIKit

/// AltLoad acting as AltServer for the AltStore on this iPhone.
///
/// AltStore signs apps itself; it only needs "a server" to put them on the device,
/// manage provisioning profiles and hand it anisette data. It looks in two places:
///
/// 1. **On-device link (preferred).** AltStore posts the Darwin notification
///    `io.altstore.Request.WiredServerConnectionAvailable` and waits one second for
///    `…Response.WiredServerConnectionAvailable`. If it gets one, it treats the server
///    as connected over USB, posts `…Request.WiredServerConnectionStart` and waits for
///    that server to connect to it on 127.0.0.1:28151. AltLoad answers both, so AltStore
///    picks it before any AltServer on the network.
/// 2. **Wi-Fi.** A Bonjour `_altserver._tcp` service whose TXT `serverID` matches the
///    ALTServerID AltLoad wrote into AltStore, which makes it AltStore's preferred server.
///
/// Requests use AltServer's protocol: a little-endian Int32 length, then JSON.
/// One request per connection. The device work (installation_proxy, AFC, misagent)
/// goes through LocalDevVPN via DeviceOps.
///
/// iOS pauses AltLoad in the background, so it only answers while it's open or kept
/// awake (silent audio).
@MainActor
final class AltServerHost: ObservableObject {
    static let shared = AltServerHost()

    struct Event: Identifiable {
        enum Kind { case info, success, failure }
        let id = UUID()
        let date = Date()
        let title: String
        let detail: String?
        let kind: Kind
    }

    struct Activity: Equatable {
        var title: String
        var stage: String
        var fraction: Double?
    }

    @Published var isEnabled: Bool = UserDefaults.standard.object(forKey: "altserver.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "altserver.enabled")
            if isEnabled { start() } else { stop() }
            applyKeepAwake()
        }
    }

    /// Plays silent audio so AltLoad keeps answering AltStore from the background.
    @Published var keepAwake: Bool = UserDefaults.standard.bool(forKey: "altserver.keepAwake") {
        didSet {
            UserDefaults.standard.set(keepAwake, forKey: "altserver.keepAwake")
            applyKeepAwake()
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var wifiState = "Off"
    @Published private(set) var events: [Event] = []
    @Published private(set) var activity: Activity?
    /// Last time AltStore looked for a server.
    @Published private(set) var lastContact: Date?

    static let wiredPort: UInt16 = 28151
    private static let availableRequest = "io.altstore.Request.WiredServerConnectionAvailable"
    private static let availableResponse = "io.altstore.Response.WiredServerConnectionAvailable"
    private static let startRequest = "io.altstore.Request.WiredServerConnectionStart"

    private var listener: NWListener?
    private let keepAlive = KeepAlive()
    private let queue = DispatchQueue(label: "altload.altserver")

    private init() {}

    // MARK: - Lifecycle

    func startIfEnabled() {
        if isEnabled { start() }
        applyKeepAwake()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        observeDarwinNotifications()
        startWiFiListener()
        log("AltServer started", detail: "AltStore on this iPhone can now find AltLoad.", kind: .info)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque())
        listener?.cancel()
        listener = nil
        wifiState = "Off"
        log("AltServer stopped", detail: nil, kind: .info)
    }

    /// Re-arms the Wi-Fi listener after coming back to the foreground.
    func refresh() {
        guard isRunning else { return }
        if listener == nil { startWiFiListener() }
        applyKeepAwake()
    }

    private func applyKeepAwake() {
        if isEnabled && keepAwake {
            keepAlive.startAudio()
        } else {
            keepAlive.stopAudio()
        }
    }

    func clearLog() { events.removeAll() }

    private func log(_ title: String, detail: String?, kind: Event.Kind) {
        events.insert(Event(title: title, detail: detail, kind: kind), at: 0)
        if events.count > 40 { events.removeLast(events.count - 40) }
    }

    // MARK: - On-device link (Darwin notifications)

    private func observeDarwinNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in [Self.availableRequest, Self.startRequest] {
            CFNotificationCenterAddObserver(center, observer, altServerDarwinCallback, name as CFString, nil, .deliverImmediately)
        }
    }

    fileprivate func handleDarwin(_ name: String) {
        guard isRunning else { return }
        lastContact = .now
        switch name {
        case Self.availableRequest:
            // Answer straight away: AltStore only waits one second.
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(Self.availableResponse as CFString), nil, nil, true)
        case Self.startRequest:
            let connection = NWConnection(
                host: "127.0.0.1",
                port: NWEndpoint.Port(rawValue: Self.wiredPort)!,
                using: .tcp)
            serve(connection, via: "on-device link")
        default:
            break
        }
    }

    // MARK: - Wi-Fi (Bonjour)

    private func startWiFiListener() {
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = false
            let listener = try NWListener(using: parameters)
            var txt = NWTXTRecord()
            txt["serverID"] = InstallController.serverID
            listener.service = NWListener.Service(
                name: "AltLoad (\(UIDevice.current.name))", type: "_altserver._tcp", domain: nil, txtRecord: txt)
            listener.stateUpdateHandler = { state in
                let text: String
                switch state {
                case .ready: text = "Advertising"
                case .waiting(let error): text = "Waiting: \(error.localizedDescription)"
                case .failed(let error): text = "Failed: \(error.localizedDescription)"
                case .cancelled: text = "Off"
                default: text = "Starting"
                }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let host = AltServerHost.shared
                        host.wifiState = text
                        if case .failed = state { host.listener = nil }
                    }
                }
            }
            listener.newConnectionHandler = { connection in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { AltServerHost.shared.serve(connection, via: "Wi-Fi") }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            wifiState = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Requests

    private func serve(_ connection: NWConnection, via route: String) {
        lastContact = .now
        let session = AltServerSession(connection: connection, queue: queue)
        Task { await handle(session, via: route) }
    }

    private func handle(_ session: AltServerSession, via route: String) async {
        do {
            try await session.open()
            let request = try await session.receiveMessage()
            let identifier = request["identifier"] as? String ?? ""
            switch identifier {
            case "AnisetteDataRequest":
                let data = try await AnisetteV1.fetch(from: InstallController.shared.anisetteURL)
                try await session.send(["version": 1, "identifier": "AnisetteDataResponse", "anisetteData": data])
                log("Sent anisette data", detail: "AltStore is signing in (\(route)).", kind: .info)

            case "PrepareAppRequest":
                try await installApp(request, session: session, route: route)

            case "InstallProvisioningProfilesRequest":
                let profiles = (request["provisioningProfiles"] as? [String] ?? []).compactMap { Data(base64Encoded: $0) }
                let paths = try profiles.map { data -> String in
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".mobileprovision")
                    try data.write(to: url)
                    return url.path
                }
                defer { paths.forEach { try? FileManager.default.removeItem(atPath: $0) } }
                var op: [String: Any] = ["op": "install_profiles", "paths": paths]
                if let active = request["activeProfiles"] as? [String] { op["activeProfiles"] = active }
                try await runDeviceOp(op, title: "Refreshing app profiles")
                try await session.send(["version": 1, "identifier": "InstallProvisioningProfilesResponse"])
                log("Installed \(profiles.count) provisioning profile\(profiles.count == 1 ? "" : "s")",
                    detail: "AltStore refreshed apps (\(route)).", kind: .success)

            case "RemoveProvisioningProfilesRequest":
                let ids = request["bundleIdentifiers"] as? [String] ?? []
                try await runDeviceOp(["op": "remove_profiles", "bundleIds": ids], title: "Deactivating apps")
                try await session.send(["version": 1, "identifier": "RemoveProvisioningProfilesResponse"])
                log("Removed profiles", detail: ids.joined(separator: ", "), kind: .success)

            case "RemoveAppRequest":
                let bundleID = request["bundleIdentifier"] as? String ?? ""
                try await runDeviceOp(["op": "remove_app", "bundleId": bundleID], title: "Removing an app")
                try await session.send(["version": 1, "identifier": "RemoveAppResponse"])
                log("Removed \(bundleID)", detail: nil, kind: .success)

            case "EnableUnsignedCodeExecutionRequest":
                throw HostError.message("AltLoad can't enable JIT. Use StikDebug for that.")

            default:
                throw HostError.message("AltLoad doesn't support \"\(identifier)\" yet.")
            }
        } catch {
            try? await session.send(Self.errorResponse(error))
            log("AltStore request failed", detail: error.localizedDescription, kind: .failure)
        }
        activity = nil
        await session.close(after: 1)
    }

    private func installApp(_ request: [String: Any], session: AltServerSession, route: String) async throws {
        let size = (request["contentSize"] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw HostError.message("AltStore sent an empty app.") }

        activity = Activity(title: "AltStore is installing an app", stage: "Receiving the app…", fraction: 0)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
        defer { try? FileManager.default.removeItem(at: file) }
        try await session.receive(size, into: file) { fraction in
            Task { @MainActor in AltServerHost.shared.activity?.fraction = fraction * 0.15 }
        }

        let begin = try await session.receiveMessage()
        guard begin["identifier"] as? String == "BeginInstallationRequest" else {
            throw HostError.message("AltStore didn't start the installation.")
        }
        let bundleID = begin["bundleIdentifier"] as? String

        var op: [String: Any] = ["op": "install_app", "path": file.path]
        if let active = begin["activeProfiles"] as? [String] { op["activeProfiles"] = active }

        let reporter = ProgressReporter(session: session)
        try await DeviceOps.run(op) { stage, fraction in
            AltServerHost.shared.activity?.stage = stage
            if let fraction {
                AltServerHost.shared.activity?.fraction = 0.15 + fraction * 0.85
                reporter.report(fraction)
            }
        }
        try await session.send(["version": 1, "identifier": "InstallationProgressResponse", "progress": 1.0])
        log("Installed \(bundleID ?? "an app")", detail: "Through AltLoad's AltServer (\(route)).", kind: .success)
    }

    private func runDeviceOp(_ op: [String: Any], title: String) async throws {
        activity = Activity(title: title, stage: "Opening device link…", fraction: nil)
        try await DeviceOps.run(op) { stage, fraction in
            AltServerHost.shared.activity?.stage = stage
            AltServerHost.shared.activity?.fraction = fraction
        }
    }

    private enum HostError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }

    /// AltServer's ErrorResponse (v3). The domain is AltLoad's own, so AltStore
    /// shows the ALTLocalized… strings as the message.
    private static func errorResponse(_ error: Error) -> [String: Any] {
        let message = error.localizedDescription
        return [
            "version": 3,
            "identifier": "ErrorResponse",
            "errorCode": 0,
            "serverError": [
                "errorDomain": "AltLoad.AltServer",
                "errorCode": 1,
                "errorUserInfo": [
                    "ALTLocalizedDescription": message,
                    "ALTLocalizedFailureReason": message,
                ],
                "userInfo": [NSLocalizedDescriptionKey: message],
            ] as [String: Any],
        ]
    }
}

private let altServerDarwinCallback: CFNotificationCallback = { _, _, name, _, _ in
    guard let cfName = name?.rawValue else { return }
    let raw = cfName as String
    DispatchQueue.main.async {
        MainActor.assumeIsolated { AltServerHost.shared.handleDarwin(raw) }
    }
}

/// Sends InstallationProgressResponse updates to AltStore, one at a time, never 1.0
/// (AltStore treats 1.0 as "done").
private final class ProgressReporter: @unchecked Sendable {
    private let session: AltServerSession
    private let lock = NSLock()
    private var sending = false

    init(session: AltServerSession) { self.session = session }

    func report(_ fraction: Double) {
        let claimed = lock.withLock { () -> Bool in
            guard !sending else { return false }
            sending = true
            return true
        }
        guard claimed else { return }
        let value = min(max(fraction, 0), 0.99)
        Task {
            try? await session.send(["version": 1, "identifier": "InstallationProgressResponse", "progress": value])
            lock.withLock { sending = false }
        }
    }
}

// MARK: - Connection

/// One AltServer-protocol connection: Int32 little-endian length + JSON, plus raw app data.
final class AltServerSession: @unchecked Sendable {
    enum SessionError: LocalizedError {
        case closed, badMessage
        var errorDescription: String? {
            switch self {
            case .closed: "AltStore closed the connection."
            case .badMessage: "AltStore sent something AltLoad couldn't read."
            }
        }
    }

    private let connection: NWConnection
    private let queue: DispatchQueue

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume() }
                case .failed(let error): once.run { continuation.resume(throwing: error) }
                case .cancelled: once.run { continuation.resume(throwing: SessionError.closed) }
                default: break
                }
            }
            connection.start(queue: queue)
        }
    }

    func close(after seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
        connection.cancel()
    }

    private func receiveChunk(max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content, !content.isEmpty {
                    continuation.resume(returning: content)
                } else if isComplete {
                    continuation.resume(throwing: SessionError.closed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    func receive(_ count: Int) async throws -> Data {
        var data = Data()
        while data.count < count {
            data.append(try await receiveChunk(max: count - data.count))
        }
        return data
    }

    /// Streams `count` bytes straight to a file (apps can be hundreds of MB).
    func receive(_ count: Int, into file: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var received = 0
        var lastReported = 0.0
        while received < count {
            let chunk = try await receiveChunk(max: min(count - received, 1 << 20))
            try handle.write(contentsOf: chunk)
            received += chunk.count
            let fraction = Double(received) / Double(count)
            if fraction - lastReported >= 0.02 || received == count {
                lastReported = fraction
                progress(fraction)
            }
        }
    }

    func receiveMessage() async throws -> [String: Any] {
        let header = try await receive(4)
        let size = Int(Int32(littleEndian: header.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }))
        guard size > 0, size < 64 << 20 else { throw SessionError.badMessage }
        let body = try await receive(size)
        guard let message = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw SessionError.badMessage
        }
        return message
    }

    func send(_ message: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: message)
        var size = Int32(body.count).littleEndian
        var packet = Data(bytes: &size, count: MemoryLayout<Int32>.size)
        packet.append(body)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}

/// Runs a closure at most once (continuations must be resumed exactly once).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        let first = lock.withLock { () -> Bool in
            defer { done = true }
            return !done
        }
        if first { body() }
    }
}

// MARK: - Anisette for AltStore

/// AltStore asks AltServer for anisette data (ALTAnisetteData JSON). Anisette
/// servers answer a plain GET with the headers of their own device ("v1"),
/// which is what AltServer on Windows/Linux setups used as well.
enum AnisetteV1 {
    enum AnisetteError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            if case .unsupported(let host) = self {
                return "\(host) didn't return anisette data AltStore can use. Pick another anisette server in AltLoad's Settings."
            }
            return nil
        }
    }

    static func fetch(from urlString: String) async throws -> [String: String] {
        guard let url = URL(string: urlString) else { throw AnisetteError.unsupported(urlString) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnisetteError.unsupported(url.host() ?? urlString)
        }
        var headers: [String: String] = [:]
        for (key, value) in raw {
            headers[key.lowercased()] = (value as? String) ?? (value as? NSNumber)?.stringValue
        }
        func h(_ key: String) -> String? { headers[key.lowercased()].flatMap { $0.isEmpty ? nil : $0 } }

        guard let machineID = h("X-Apple-I-MD-M"), let otp = h("X-Apple-I-MD") else {
            throw AnisetteError.unsupported(url.host() ?? urlString)
        }
        let deviceID = h("X-Mme-Device-Id") ?? UUID().uuidString.uppercased()
        let localUserID = h("X-Apple-I-MD-LU")
            ?? SHA256.hash(data: Data(deviceID.utf8)).map { String(format: "%02X", $0) }.joined()

        return [
            "machineID": machineID,
            "oneTimePassword": otp,
            "localUserID": localUserID,
            "routingInfo": h("X-Apple-I-MD-RINFO") ?? "17106176",
            "deviceUniqueIdentifier": deviceID,
            "deviceSerialNumber": h("X-Apple-I-SRL-NO") ?? "0",
            "deviceDescription": h("X-MMe-Client-Info")
                ?? "<MacBookPro15,1> <Mac OS X;10.15.2;19C57> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>",
            "date": h("X-Apple-I-Client-Time") ?? ISO8601DateFormatter().string(from: .now),
            "locale": h("X-Apple-Locale") ?? Locale.current.identifier,
            "timeZone": h("X-Apple-I-TimeZone") ?? (TimeZone.current.abbreviation() ?? "UTC"),
        ]
    }
}
