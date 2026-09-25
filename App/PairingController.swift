// Pairing flow adapted from StikPair (c) 2026 StephenDev0 — see LICENSE.
import BackgroundTasks
import Combine
import Foundation
import AltLoadFFI
import UserNotifications

@MainActor
final class PairingController: ObservableObject {

    static let shared = PairingController()
    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.altload.AltLoad") + ".pairing"

    enum Phase: Equatable {
        case idle
        case waiting
        case showPin(String)
        case browsingAppleTV
        case enteringAppleTVPin(AppleTVDevice)
        case pairingAppleTV(String)
        case success(SavedPairing)
        case failed(String)
    }

    /// What the Rust side reports, before the file is moved into the store.
    private enum RawOutcome {
        case paired(name: String, model: String, udid: String, path: String)
        case failed(String)
    }

    @Published var phase: Phase = .idle
    @Published private(set) var appleTVs: [AppleTVDevice] = []

    @Published var keepAliveAudio: Bool = UserDefaults.standard.bool(forKey: "keepAlive.audio") {
        didSet { UserDefaults.standard.set(keepAliveAudio, forKey: "keepAlive.audio") }
    }
    @Published var keepAliveLocation: Bool = UserDefaults.standard.bool(forKey: "keepAlive.location") {
        didSet { UserDefaults.standard.set(keepAliveLocation, forKey: "keepAlive.location") }
    }

    private let bindAddress = "0.0.0.0"
    /// Shown on the other device as "Pair with AltLoad".
    private let hostName = "AltLoad"

    private let store = PairingStore.shared
    private var netService: NetService?
    private let localNetwork = LocalNetworkAuthorization()
    private let keepAlive = KeepAlive()
    private let appleTVDiscovery = AppleTVDiscovery()
    private var discoverySubscription: AnyCancellable?
    private var appleTVSession: OpaquePointer?
    private var activeAppleTV: AppleTVDevice?
    private var appleTVCancelled = false

    private var bgTask: BGContinuedProcessingTask?
    private var pairingStarted = false
    private var taskFinished = false

    var isRunning: Bool {
        if pairingStarted { return true }
        switch phase {
        case .waiting, .showPin, .enteringAppleTVPin, .pairingAppleTV: return true
        default: return false
        }
    }

    private init() {
        discoverySubscription = appleTVDiscovery.$devices
            .sink { [weak self] devices in self?.appleTVs = devices }
    }

    nonisolated func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: PairingController.taskIdentifier,
            using: DispatchQueue.main
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else { return }
            MainActor.assumeIsolated {
                PairingController.shared.runPairing(task: task)
            }
        }
    }

    // MARK: - iPhone / iPad

    func start() {
        guard !isRunning else { return }
        phase = .waiting

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        if keepAliveAudio { keepAlive.startAudio() }
        if keepAliveLocation { keepAlive.startLocation() }

        Task {
            guard await localNetwork.request() else {
                keepAlive.stopAll()
                phase = .failed(Self.localNetworkMessage)
                return
            }
            submitBackgroundTask()
        }
    }

    // MARK: - Apple TV

    func browseForAppleTVs() {
        guard !isRunning else { return }
        phase = .browsingAppleTV
        Task {
            let authorized = await localNetwork.request()
            guard case .browsingAppleTV = phase else { return }
            guard authorized else {
                phase = .failed(Self.localNetworkMessage)
                return
            }
            appleTVDiscovery.start()
        }
    }

    func pairAppleTV(_ device: AppleTVDevice) {
        guard !pairingStarted, let session = altload_apple_tv_session_new() else { return }
        appleTVDiscovery.stop()
        appleTVSession = session
        activeAppleTV = device
        appleTVCancelled = false
        pairingStarted = true
        phase = .pairingAppleTV(device.name)

        let name = hostName
        let outPath = PairingPaths.temporaryPath()
        let sessionBits = UInt(bitPattern: session)
        let ctxBits = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        DispatchQueue.global(qos: .userInitiated).async {
            guard let session = OpaquePointer(bitPattern: sessionBits) else { return }
            let ctx = UnsafeMutableRawPointer(bitPattern: ctxBits)
            var result = AltLoadResult()
            let rc = device.host.withCString { hostC in
                name.withCString { nameC in
                    outPath.withCString { outC in
                        altload_apple_tv_session_run(
                            session, hostC, UInt16(device.port), nameC, outC,
                            appleTVPinCallback, ctx, &result)
                    }
                }
            }
            let raw = Self.rawOutcome(rc: rc, result: result, fallback: "Apple TV pairing failed")
            altload_result_free(&result)

            DispatchQueue.main.async {
                let cancelled = self.appleTVCancelled
                if self.appleTVSession == session {
                    self.appleTVSession = nil
                }
                altload_apple_tv_session_free(session)
                self.activeAppleTV = nil
                self.pairingStarted = false
                guard !cancelled else { return }
                self.phase = self.finalize(raw)
                if case .success = self.phase {
                    self.postReturnNotification()
                }
            }
        }
    }

    func submitAppleTVPin(_ pin: String) {
        guard pin.count == 6, pin.allSatisfy(\.isNumber), let session = appleTVSession else { return }
        let rc = pin.withCString { altload_apple_tv_session_submit_pin(session, $0) }
        if rc == 0, let device = activeAppleTV {
            phase = .pairingAppleTV(device.name)
        }
    }

    func cancelAppleTVPairing() {
        appleTVCancelled = true
        if let session = appleTVSession {
            altload_apple_tv_session_cancel(session)
        }
        appleTVDiscovery.stop()
        phase = .idle
    }

    func reset() {
        guard !isRunning else { return }
        appleTVDiscovery.stop()
        phase = .idle
    }

    // MARK: - Host pairing (runs while the user is in Settings)

    private func submitBackgroundTask() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: PairingController.taskIdentifier,
            title: "AltLoad",
            subtitle: "Waiting for a device to connect…")
        request.strategy = .queue

        do {
            try BGTaskScheduler.shared.submit(request)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, !self.pairingStarted else { return }
                self.runPairing(task: nil)
            }
        } catch {
            runPairing(task: nil)
        }
    }

    private func runPairing(task: BGContinuedProcessingTask?) {
        guard !pairingStarted else { return }
        pairingStarted = true
        taskFinished = false
        bgTask = task

        task?.progress.totalUnitCount = 100
        task?.progress.completedUnitCount = 5
        task?.expirationHandler = { [weak self] in
            guard let self else { return }
            self.keepAlive.stopAll()
            self.finishTask(success: false)
            if self.isRunning {
                self.phase = .failed("Background time expired before a device connected. Tap Pair to try again.")
            }
        }

        let bind = bindAddress
        let name = hostName
        let outPath = PairingPaths.temporaryPath()
        let ctxBits = UInt(bitPattern: Unmanaged.passRetained(self).toOpaque())

        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = UnsafeMutableRawPointer(bitPattern: ctxBits)
            var result = AltLoadResult()
            let rc = bind.withCString { bindC in
                name.withCString { nameC in
                    "Mac17,7".withCString { modelC in
                        outPath.withCString { outC in
                            altload_run_host(
                                bindC, 0, nameC, modelC, outC,
                                readyCallback, pinCallback, ctx, &result)
                        }
                    }
                }
            }
            let raw = Self.rawOutcome(rc: rc, result: result, fallback: "Pairing failed")
            altload_result_free(&result)
            if let ctx = ctx { Unmanaged<PairingController>.fromOpaque(ctx).release() }

            DispatchQueue.main.async {
                self.stopAdvertising()
                self.keepAlive.stopAll()
                self.pairingStarted = false
                self.phase = self.finalize(raw)
                let succeeded: Bool
                if case .success = self.phase { succeeded = true } else { succeeded = false }
                if succeeded {
                    self.bgTask?.progress.completedUnitCount = 100
                    self.postReturnNotification()
                }
                self.finishTask(success: succeeded)
            }
        }
    }

    private nonisolated static func rawOutcome(rc: Int32, result: AltLoadResult, fallback: String) -> RawOutcome {
        if rc == 0 {
            return .paired(
                name: cString(result.device_name),
                model: cString(result.device_model),
                udid: cString(result.device_udid),
                path: cString(result.pairing_file_path))
        }
        let message = cString(result.error)
        return .failed(message.isEmpty ? "\(fallback) (code \(rc))" : message)
    }

    private func finalize(_ raw: RawOutcome) -> Phase {
        switch raw {
        case .failed(let message):
            return .failed(message)
        case .paired(let name, let model, let udid, let path):
            do {
                let saved = try store.save(fromTemporaryPath: path, name: name, model: model, udid: udid)
                return .success(saved)
            } catch {
                return .failed("Paired, but the pairing file couldn't be saved: \(error.localizedDescription)")
            }
        }
    }

    private func finishTask(success: Bool) {
        guard !taskFinished else { return }
        taskFinished = true
        bgTask?.setTaskCompleted(success: success)
        bgTask = nil
    }

    fileprivate func startAdvertising(serviceID: String, port: Int32, txt: [String: Data]) {
        stopAdvertising()
        let service = NetService(
            domain: "",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: port)
        service.setTXTRecord(NetService.data(fromTXTRecord: txt))
        service.publish()
        netService = service
    }

    fileprivate func presentPin(_ pin: String) {
        phase = .showPin(pin)
        bgTask?.progress.completedUnitCount = 50
        bgTask?.updateTitle("AltLoad", subtitle: "Enter code \(pin) on this device")
        if keepAliveAudio || keepAliveLocation {
            notify(id: "altload.pin",
                   title: "AltLoad pairing code",
                   body: "Enter \(pin) on this device to pair.")
        }
    }

    fileprivate func presentAppleTVPin() {
        guard !appleTVCancelled, let device = activeAppleTV else { return }
        phase = .enteringAppleTVPin(device)
    }

    private func stopAdvertising() {
        netService?.stop()
        netService = nil
    }

    private func postReturnNotification() {
        notify(id: "altload.done",
               title: "Pairing complete",
               body: "Return to AltLoad to export the pairing file.")
    }

    private func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static let localNetworkMessage =
        "Local Network permission is required. Enable it in Settings › AltLoad › Local Network, then try again."
}

// MARK: - C callbacks

private let readyCallback: AltLoadReadyCb = { ctx, serviceID, port, keys, vals, count in
    guard let ctx = ctx, let serviceID = serviceID else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    let id = String(cString: serviceID)

    var txt: [String: Data] = [:]
    if let keys = keys, let vals = vals {
        for i in 0..<Int(count) {
            guard let k = keys[i], let v = vals[i] else { continue }
            txt[String(cString: k)] = Data(String(cString: v).utf8)
        }
    }

    DispatchQueue.main.async {
        controller.startAdvertising(serviceID: id, port: Int32(port), txt: txt)
    }
}

private let pinCallback: AltLoadPinCb = { pin, ctx in
    guard let ctx = ctx, let pin = pin else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    let pinString = String(cString: pin)
    DispatchQueue.main.async {
        controller.presentPin(pinString)
    }
}

private let appleTVPinCallback: AltLoadAppleTvPinCb = { ctx in
    guard let ctx = ctx else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async {
        controller.presentAppleTVPin()
    }
}

private func cString(_ ptr: UnsafeMutablePointer<CChar>?) -> String {
    guard let ptr = ptr else { return "" }
    return String(cString: ptr)
}
