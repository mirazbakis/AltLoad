import Foundation

/// What a log line is about.
enum LogCategory: String, CaseIterable, Identifiable, Sendable {
    case install, account, pairing, jit, altserver, vpn, app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .install: String(localized: "Install")
        case .account: String(localized: "Account")
        case .pairing: String(localized: "Pairing")
        case .jit: String(localized: "JIT")
        case .altserver: String(localized: "AltServer")
        case .vpn: String(localized: "VPN")
        case .app: String(localized: "App")
        }
    }
}

struct LogLine: Identifiable, Hashable, Sendable {
    enum Level: String, Sendable { case info, error }

    let id: Int
    let date: Date
    let category: LogCategory
    let level: Level
    let text: String

    /// One line of the exported log.
    var formatted: String {
        let mark = level == .error ? " ERROR" : ""
        return "\(AppLog.timestamp(date)) [\(category.rawValue)]\(mark) \(text)"
    }
}

/// AltLoad's log: timestamped lines kept in memory and in
/// Application Support/AltLoad/Logs/altload.log, so they can go into a bug report.
/// Safe from any thread or actor. Lines are redacted before they're stored.
final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    /// Posted on the main queue after lines are added or cleared.
    static let didChange = Notification.Name("AppLog.didChange")

    private static let maxLines = 3000
    private static let maxFileBytes = 400 * 1024

    private let queue = DispatchQueue(label: "AltLoad.log")
    private var lines: [LogLine] = []
    private var nextID = 0
    private var notifyPending = false
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AltLoad/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("altload.log")
        queue.sync { loadFromDisk() }
    }

    // MARK: - Writing

    func info(_ category: LogCategory, _ text: String) {
        add(category, text, level: .info)
    }

    func error(_ category: LogCategory, _ text: String) {
        add(category, text, level: .error)
    }

    func add(_ category: LogCategory, _ text: String, level: LogLine.Level = .info) {
        let clean = Self.redact(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let date = Date()
        queue.async { [self] in
            let line = LogLine(id: nextID, date: date, category: category, level: level, text: clean)
            nextID += 1
            lines.append(line)
            if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
            append(line)
            scheduleNotify()
        }
    }

    func clear() {
        queue.async { [self] in
            lines.removeAll()
            try? Data().write(to: fileURL, options: .atomic)
            scheduleNotify()
        }
    }

    // MARK: - Reading

    func snapshot() -> [LogLine] {
        queue.sync { lines }
    }

    /// The whole log as text.
    func text(_ subset: [LogLine]? = nil) -> String {
        (subset ?? snapshot()).map(\.formatted).joined(separator: "\n")
    }

    /// A temporary .txt copy of `lines`, for sharing.
    func exportFile(_ subset: [LogLine]? = nil) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AltLoad-log.txt")
        let body = Self.deviceSummary + "\n\n" + text(subset) + "\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A short report for an issue: versions, the error and the last lines.
    func report(error: String, lastLines: Int = 80) -> String {
        let tail = snapshot().suffix(lastLines).map(\.formatted).joined(separator: "\n")
        return """
        \(Self.deviceSummary)

        Error:
        \(Self.redact(error))

        Last \(min(lastLines, snapshot().count)) log lines:
        \(tail)
        """
    }

    // MARK: - Device

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        let pre = info?["AltLoadPrerelease"] as? String ?? ""
        return pre.isEmpty ? "\(v) (\(b))" : "\(v) \(pre) (\(b))"
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// The hardware identifier, e.g. iPhone17,1.
    static var deviceModel: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return "\(sim) (Simulator)" }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var deviceSummary: String {
        "AltLoad \(appVersion) · \(systemVersion) · \(deviceModel)"
    }

    // MARK: - Redaction

    /// Masks Apple ID emails and drops anything that looks like a token or key.
    static func redact(_ text: String) -> String {
        var out = text
        out = replace(emailPattern, in: out) { match in maskEmail(match) }
        // Long base64 runs: tokens, anisette data, certificates.
        // Paths are long too, but split into short parts.
        out = replace(tokenPattern, in: out) { match in
            match.split(separator: "/").contains { $0.count >= 48 } ? "[redacted]" : match
        }
        // key=value or "key": value pairs that name a secret.
        out = replace(secretPairPattern, in: out) { match in
            let parts = match.split(maxSplits: 1, whereSeparator: { $0 == "=" || $0 == ":" })
            return "\(parts.first ?? "")=[redacted]"
        }
        return out
    }

    static func maskEmail(_ email: String) -> String {
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2, let first = parts[0].first else { return email }
        return "\(first)***@\(parts[1])"
    }

    private static let emailPattern = try! NSRegularExpression(
        pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: [.caseInsensitive])
    private static let tokenPattern = try! NSRegularExpression(
        pattern: "[A-Za-z0-9+/_-]{48,}={0,2}")
    private static let secretPairPattern = try! NSRegularExpression(
        pattern: "\"?(password|passwd|token|X-Apple-I-MD(-M)?)\"?\\s*[=:]\\s*\"?[^\\s\",}]+\"?",
        options: [.caseInsensitive])

    private static func replace(_ regex: NSRegularExpression, in text: String, with transform: (String) -> String) -> String {
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += transform(ns.substring(with: match.range))
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    // MARK: - File (on `queue`)

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func timestamp(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }

    /// One entry per line: date, category, level and text, tab-separated.
    private func encode(_ line: LogLine) -> String {
        let text = line.text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: " ")
        return "\(Self.isoFormatter.string(from: line.date))\t\(line.category.rawValue)\t\(line.level.rawValue)\t\(text)\n"
    }

    private func decode(_ row: Substring) -> (Date, LogCategory, LogLine.Level, String)? {
        let fields = row.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count == 4,
              let date = Self.isoFormatter.date(from: String(fields[0])),
              let category = LogCategory(rawValue: String(fields[1])) else { return nil }
        let level = LogLine.Level(rawValue: String(fields[2])) ?? .info
        var text = ""
        var escaped = false
        for c in fields[3] {
            if escaped {
                text.append(c == "n" ? "\n" : c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                text.append(c)
            }
        }
        return (date, category, level, text)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL), let body = String(data: data, encoding: .utf8) else { return }
        for row in body.split(separator: "\n") {
            guard let (date, category, level, text) = decode(row) else { continue }
            lines.append(LogLine(id: nextID, date: date, category: category, level: level, text: text))
            nextID += 1
        }
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    private func append(_ line: LogLine) {
        let data = Data(encode(line).utf8)
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if size + data.count > Self.maxFileBytes {
            rewrite()
            return
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Keeps the newest lines that fit in about half the file cap.
    private func rewrite() {
        var kept: [String] = []
        var bytes = 0
        for line in lines.reversed() {
            let row = encode(line)
            bytes += row.utf8.count
            if bytes > Self.maxFileBytes / 2 { break }
            kept.append(row)
        }
        try? Data(kept.reversed().joined().utf8).write(to: fileURL, options: .atomic)
    }

    private func scheduleNotify() {
        guard !notifyPending else { return }
        notifyPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            queue.async { self.notifyPending = false }
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }
}
