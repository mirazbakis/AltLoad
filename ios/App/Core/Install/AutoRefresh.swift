import BackgroundTasks
import Foundation
@preconcurrency import UserNotifications

/// Refreshes apps on its own: ones that expire within two days, and ones whose
/// signing certificate is gone from the Apple ID (revoked by Apple or anyone
/// else), which stop opening at once. A refresh signs the app again, which gets a
/// new provisioning profile and, when the old certificate is gone, a new one.
/// Certificates are checked against the Apple ID's developer account
/// (CertificateCheck), at most once a day per Apple ID.
///
/// It runs when AltLoad comes to the front and in a background task iOS starts
/// when it sees fit (usually overnight). Each refresh needs LocalDevVPN on and the
/// Apple ID's password saved; anything that needs the user (two-factor, a full
/// set of certificates) stops it and AltLoad says so in a notification.
@MainActor
final class AutoRefresh: ObservableObject {
    static let shared = AutoRefresh()

    static let taskIdentifier = (Bundle.main.bundleIdentifier ?? "com.mirazbakis.altload") + ".autorefresh"
    private static let enabledKey = "autoRefresh.enabled"
    private static let lastRunKey = "autoRefresh.lastRun"
    private static let revokedKey = "autoRefresh.revoked"
    private static let accountChecksKey = "autoRefresh.accountChecks"
    /// How often each Apple ID's certificates are checked.
    private static let accountInterval: TimeInterval = 24 * 60 * 60
    /// Apps are refreshed this long before they expire.
    static let window: TimeInterval = 2 * 24 * 60 * 60
    /// Checks from coming to the front are at most this often, unless an app is about to expire.
    private static let foregroundInterval: TimeInterval = 6 * 60 * 60

    @Published var enabled: Bool = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            enabled ? schedule() : BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        }
    }
    @Published private(set) var running = false
    @Published private(set) var lastRun: Date? = UserDefaults.standard.object(forKey: lastRunKey) as? Date
    /// Bundle IDs whose certificate was found revoked and not yet re-signed.
    @Published private(set) var revoked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: revokedKey) ?? [])

    private var notified: Set<String> = []

    private init() {}

    // MARK: - Background task

    /// Call once at launch, before the app finishes launching.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            Task { @MainActor in AutoRefresh.shared.handle(task) }
        }
    }

    /// Asks iOS for the next background run, around when the next app needs one.
    func schedule() {
        guard enabled else { return }
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        let due = InstallController.shared.apps
            .compactMap { $0.expiration?.addingTimeInterval(-Self.window) }
            .min() ?? .now.addingTimeInterval(24 * 60 * 60)
        // Revocations can come any day, so look at least daily.
        request.earliestBeginDate = min(max(due, .now.addingTimeInterval(15 * 60)), .now.addingTimeInterval(24 * 60 * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGTask) {
        let work = Task { @MainActor in
            await run()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in InstallController.shared.cancel() }
        }
        schedule()
    }

    // MARK: - Checks

    /// From coming to the front: runs if it's been a while or something is due.
    func checkIfDue() {
        guard enabled else { return }
        let urgent = InstallController.shared.apps.contains { needsRefresh($0, by: .now.addingTimeInterval(24 * 60 * 60)) }
        if urgent || lastRun.map({ Date.now.timeIntervalSince($0) > Self.foregroundInterval }) ?? true {
            Task { await run() }
        }
        schedule()
    }

    /// Checks every app AltLoad signed and refreshes the ones that need it.
    func run() async {
        guard enabled, !running else { return }
        running = true
        defer {
            running = false
            lastRun = .now
            UserDefaults.standard.set(lastRun, forKey: Self.lastRunKey)
        }

        let controller = InstallController.shared
        await checkCertificates(controller.apps)

        let due = controller.apps.filter { app in
            app.refreshTarget != nil && (revoked.contains(app.bundleID) || needsRefresh(app, by: .now.addingTimeInterval(Self.window)))
        }
        for app in due {
            if Task.isCancelled { return }
            await refresh(app)
        }
    }

    private func needsRefresh(_ app: InstalledApp, by date: Date) -> Bool {
        guard app.refreshTarget != nil, let expiration = app.expiration else { return false }
        return expiration <= date
    }

    /// Checks each Apple ID's active certificates (once a day) and marks the apps
    /// whose profile names one that's gone.
    private func checkCertificates(_ apps: [InstalledApp]) async {
        var checks = UserDefaults.standard.dictionary(forKey: Self.accountChecksKey) as? [String: Date] ?? [:]
        var found = revoked
        let byAccount = Dictionary(grouping: apps.filter { $0.certificates?.isEmpty == false && $0.refreshTarget != nil }) {
            ($0.appleID ?? AppleIDStore.email).lowercased()
        }
        for (account, accountApps) in byAccount where !account.isEmpty {
            if Task.isCancelled { return }
            if let last = checks[account], Date.now.timeIntervalSince(last) < Self.accountInterval { continue }
            guard let password = AppleIDStore.password(for: account) else { continue }
            let anisette = await AnisetteServers.shared.signInList(preferred: InstallController.shared.anisetteURL)
            guard let active = await CertificateCheck.activeSerials(
                for: AppleIDCredentials(email: account, password: password), anisette: anisette) else { continue }
            checks[account] = .now
            for app in accountApps where CertificateCheck.lostCertificate(app, active: active) {
                found.insert(app.bundleID)
            }
        }
        UserDefaults.standard.set(checks, forKey: Self.accountChecksKey)
        setRevoked(found)
    }

    private func refresh(_ app: InstalledApp) async {
        let wasRevoked = revoked.contains(app.bundleID)
        let account = app.appleID ?? AppleIDStore.email
        guard !account.isEmpty, let password = AppleIDStore.password(for: account) else {
            notifyOnce(app, title: String(localized: "\(app.name) needs a refresh"),
                       body: String(localized: "AltLoad can refresh it by itself once the password for its Apple ID is saved. Open AltLoad and refresh it once with Remember password on."))
            return
        }
        guard LocalDevVPN.isActive else {
            notifyOnce(app, title: String(localized: "\(app.name) needs a refresh"),
                       body: String(localized: "Turn on LocalDevVPN, then open AltLoad, and it refreshes by itself."))
            return
        }

        let result = await InstallController.shared.refreshQuietly(app, credentials: AppleIDCredentials(email: account, password: password))
        switch result {
        case .success(let refreshed):
            var remaining = revoked
            remaining.remove(app.bundleID)
            setRevoked(remaining)
            notified.remove(app.bundleID)
            let until = refreshed.expiration?.formatted(date: .abbreviated, time: .omitted) ?? ""
            notify(app, title: wasRevoked
                    ? String(localized: "\(app.name) was signed again")
                    : String(localized: "\(app.name) was refreshed"),
                   body: wasRevoked
                    ? String(localized: "The certificate it was signed with was revoked, so AltLoad signed it with a new one. It works until \(until).")
                    : String(localized: "It works until \(until)."))
        case .failure(.busy):
            break
        case .failure(.vpnOff):
            notifyOnce(app, title: String(localized: "\(app.name) needs a refresh"),
                       body: String(localized: "Turn on LocalDevVPN, then open AltLoad, and it refreshes by itself."))
        case .failure(.failed(let reason)):
            notifyOnce(app, title: String(localized: "Couldn't refresh \(app.name)"),
                       body: String(localized: "\(reason) Open AltLoad and refresh it there."))
        }
    }

    private func setRevoked(_ set: Set<String>) {
        revoked = set
        UserDefaults.standard.set(Array(set), forKey: Self.revokedKey)
    }

    // MARK: - Notifications

    /// One "needs you" notification per app until it's refreshed, so a closed VPN
    /// doesn't bring one every run.
    private func notifyOnce(_ app: InstalledApp, title: String, body: String) {
        guard !notified.contains(app.bundleID) else { return }
        notified.insert(app.bundleID)
        notify(app, title: title, body: body)
    }

    private func notify(_ app: InstalledApp, title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: "altload.autorefresh.\(app.bundleID)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
