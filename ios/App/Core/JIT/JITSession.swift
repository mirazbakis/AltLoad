import AltLoadFFI
import Foundation
import JavaScriptCore

/// One JIT session: the Rust core launches the app suspended (or finds a running
/// process) and holds it under debugserver, and a script decides what to send.
/// Everything runs on a thread of its own, since every call blocks.
///
/// Scripts get these functions:
///   send_command(packet)                 one GDB remote packet; returns the reply
///   continue_for(resume, milliseconds)   resumes with `resume` ("c" or "vCont;S…"),
///                                        returns the stop reply, or "" if the app
///                                        stayed quiet that long (it is then paused)
///   prepare_memory_region(address, len)  makes the region usable for JIT
///   get_pid(), get_bundle_id(), log(text)
final class JITSession: @unchecked Sendable {
    /// Where the session connects, and the Developer Disk Image to mount.
    struct Target {
        let pairingPath: String
        let host: String
        let port: Int
        let ddiDirectory: String
    }

    struct Outcome {
        let pid: Int
        let requests: Int
        /// "app", "attach", "quiet", "exited", "stopped" or "script".
        let ended: String
    }

    enum Event {
        case stage(String)
        case attached(pid: Int)
        case log(String)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let lock = NSLock()
    private var handle: OpaquePointer?
    private var stopped = false

    /// Ends the session: the call in progress returns and the app is let go.
    func stop() {
        lock.lock()
        stopped = true
        if let handle { altload_debug_stop(handle) }
        lock.unlock()
    }

    func run(
        bundleID: String?,
        pid: Int?,
        script: JITScript,
        target: Target,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws -> Outcome {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { [self] in
                continuation.resume(with: Result {
                    try self.runBlocking(bundleID: bundleID, pid: pid, script: script, target: target, onEvent: onEvent)
                })
            }
            // JavaScriptCore and deep scripts want more than a secondary thread's default.
            thread.stackSize = 8 << 20
            thread.name = "AltLoad JIT"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    // MARK: - On the session thread

    private func runBlocking(
        bundleID: String?,
        pid: Int?,
        script: JITScript,
        target: Target,
        onEvent: @escaping @Sendable (Event) -> Void
    ) throws -> Outcome {
        let session = try open(bundleID: bundleID, pid: pid, target: target, onEvent: onEvent)
        defer {
            lock.lock()
            handle = nil
            lock.unlock()
            // Detaches first if the script left the app held.
            altload_debug_close(session)
        }
        let processID = Int(altload_debug_pid(session))
        onEvent(.attached(pid: processID))

        let context: JSContext = JSContext()
        var scriptError: String?
        context.exceptionHandler = { _, value in
            scriptError = value?.toString() ?? "The script failed."
        }
        install(in: context, session: session, pid: processID, bundleID: bundleID ?? "", onEvent: onEvent)

        let value = context.evaluateScript(script.source, withSourceURL: URL(string: "altload-jit:///\(script.name).js"))

        lock.lock()
        let wasStopped = stopped
        lock.unlock()
        if wasStopped {
            return Outcome(pid: processID, requests: Self.int(value?.forProperty("requests")), ended: "stopped")
        }
        if let scriptError {
            throw Failure(message: scriptError)
        }
        if let value, value.isObject, let ended = value.forProperty("ended"), ended.isString {
            return Outcome(pid: processID, requests: Self.int(value.forProperty("requests")), ended: ended.toString())
        }
        return Outcome(pid: processID, requests: 0, ended: "script")
    }

    private func open(bundleID: String?, pid: Int?, target: Target, onEvent: @escaping @Sendable (Event) -> Void) throws -> OpaquePointer {
        var request: [String: Any] = ["ddiDir": target.ddiDirectory]
        if let pid { request["pid"] = pid } else if let bundleID { request["bundleId"] = bundleID }
        let json = String(data: try JSONSerialization.data(withJSONObject: request), encoding: .utf8) ?? "{}"

        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func c(_ s: String) -> UnsafePointer<CChar>? {
            guard let p = strdup(s) else { return nil }
            owned.append(p)
            return UnsafePointer(p)
        }

        let box = EventBox(onEvent)
        var session: OpaquePointer?
        var out: UnsafeMutablePointer<CChar>?
        var endpoint = AltLoadEndpoint(host: c(target.host), port: UInt16(clamping: target.port), identifier: nil, auth_tag: nil)
        let rc: Int32 = withUnsafePointer(to: &endpoint) { endpointPointer in
            var config = AltLoadInstallConfig(
                apple_id: nil, password: nil, anisette_url: nil,
                pairing_file_path: c(target.pairingPath),
                host_name: c("AltLoad"),
                endpoints: endpointPointer,
                endpoint_count: 1,
                ipa_path: nil, device_name: nil, machine_name: nil, server_id: nil,
                capabilities: nil, extensions_mode: 0)
            let ctx = Unmanaged.passUnretained(box).toOpaque()
            return altload_debug_open(&config, json, jitProgressCallback, ctx, &session, &out)
        }
        withExtendedLifetime(box) {}
        let text = out.map { String(cString: $0) } ?? ""
        if let out { altload_string_free(out) }

        guard rc == 0, let session else {
            throw Failure(message: text.isEmpty ? String(localized: "Couldn't start the JIT session (code \(rc)).") : text)
        }
        lock.lock()
        let alreadyStopped = stopped
        if !alreadyStopped { handle = session }
        lock.unlock()
        if alreadyStopped {
            altload_debug_close(session)
            throw CancellationError()
        }
        return session
    }

    /// The functions scripts call. A failed call throws in the script.
    private func install(in context: JSContext, session: OpaquePointer, pid: Int, bundleID: String, onEvent: @escaping @Sendable (Event) -> Void) {
        func reply(_ call: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32) -> Any? {
            var out: UnsafeMutablePointer<CChar>?
            let rc = call(&out)
            let text = out.map { String(cString: $0) } ?? ""
            if let out { altload_string_free(out) }
            guard rc == 0 else {
                if let current = JSContext.current() {
                    current.exception = JSValue(newErrorFromMessage: text.isEmpty ? "debugserver call failed" : text, in: current)
                }
                return nil
            }
            return text
        }

        let sendCommand: @convention(block) (String) -> Any? = { packet in
            reply { altload_debug_send(session, packet, $0) }
        }
        let continueFor: @convention(block) (JSValue, JSValue) -> Any? = { resume, milliseconds in
            let packet = resume.isString ? resume.toString() ?? "c" : "c"
            let limit = UInt64(max(1, milliseconds.toDouble().isFinite ? milliseconds.toDouble() : 1))
            return reply { altload_debug_continue(session, packet, limit, $0) }
        }
        let prepare: @convention(block) (JSValue, JSValue) -> Any? = { address, length in
            guard let address = Self.uint64(address), let length = Self.uint64(length) else {
                JSContext.current()?.exception = JSValue(newErrorFromMessage: "prepare_memory_region needs an address and a length", in: JSContext.current())
                return nil
            }
            return reply { altload_debug_prepare(session, address, length, $0) }
        }
        let getPID: @convention(block) () -> Double = { Double(pid) }
        let getBundleID: @convention(block) () -> String = { bundleID }
        let log: @convention(block) (JSValue) -> Void = { value in
            onEvent(.log(value.toString() ?? ""))
        }

        context.setObject(sendCommand, forKeyedSubscript: "send_command" as NSString)
        context.setObject(continueFor, forKeyedSubscript: "continue_for" as NSString)
        context.setObject(prepare, forKeyedSubscript: "prepare_memory_region" as NSString)
        context.setObject(getPID, forKeyedSubscript: "get_pid" as NSString)
        context.setObject(getBundleID, forKeyedSubscript: "get_bundle_id" as NSString)
        context.setObject(log, forKeyedSubscript: "log" as NSString)
    }

    /// A BigInt, number or "0x…" string from a script.
    private static func uint64(_ value: JSValue) -> UInt64? {
        guard let text = value.toString()?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("0x") { return UInt64(text.dropFirst(2), radix: 16) }
        if let exact = UInt64(text) { return exact }
        let number = value.toDouble()
        return number.isFinite && number >= 0 ? UInt64(exactly: number.rounded()) : nil
    }

    private static func int(_ value: JSValue?) -> Int {
        guard let value, value.isNumber else { return 0 }
        return Int(value.toInt32())
    }
}

/// Carries the event handler through the C progress callback.
private final class EventBox {
    let handler: @Sendable (JITSession.Event) -> Void
    init(_ handler: @escaping @Sendable (JITSession.Event) -> Void) { self.handler = handler }
}

private let jitProgressCallback: AltLoadProgressCb = { ctx, stage, _ in
    guard let ctx, let stage else { return }
    let box = Unmanaged<EventBox>.fromOpaque(ctx).takeUnretainedValue()
    box.handler(.stage(String(cString: stage)))
}
