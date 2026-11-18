import AppIntents
import Foundation
import UIKit

/// Pinned apps, recent JIT launches and the app names AltLoad last saw, for the
/// JIT tool, Shortcuts and the Home Screen quick action.
@MainActor
final class JITFavorites: ObservableObject {
    static let shared = JITFavorites()

    struct Recent: Codable, Hashable, Identifiable {
        let bundleID: String
        let name: String
        let date: Date
        var id: String { bundleID }
    }

    static let quickActionType = "com.mirazbakis.altload.jit"
    private static let maxRecents = 8

    private let pinnedKey = "jit.pinned"
    private let recentsKey = "jit.recents"
    private let namesKey = "jit.knownApps"

    /// Pinned bundle IDs, in the order they were pinned.
    @Published private(set) var pinned: [String] {
        didSet {
            UserDefaults.standard.set(pinned, forKey: pinnedKey)
            appsChanged()
        }
    }
    /// Newest first.
    @Published private(set) var recents: [Recent] {
        didSet {
            if let data = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(data, forKey: recentsKey) }
            appsChanged()
        }
    }
    /// Bundle ID → name of the JIT-capable apps from the last app list.
    @Published private(set) var knownApps: [String: String] {
        didSet { UserDefaults.standard.set(knownApps, forKey: namesKey) }
    }

    private init() {
        pinned = UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
        recents = UserDefaults.standard.data(forKey: recentsKey)
            .flatMap { try? JSONDecoder().decode([Recent].self, from: $0) } ?? []
        knownApps = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }

    func isPinned(_ bundleID: String) -> Bool { pinned.contains(bundleID) }

    func togglePin(_ bundleID: String, name: String) {
        if let index = pinned.firstIndex(of: bundleID) {
            pinned.remove(at: index)
        } else {
            pinned.append(bundleID)
            knownApps[bundleID] = name
        }
    }

    func name(for bundleID: String) -> String {
        knownApps[bundleID] ?? recents.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    func recordLaunch(bundleID: String, name: String) {
        recents.removeAll { $0.bundleID == bundleID }
        recents.insert(Recent(bundleID: bundleID, name: name, date: .now), at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
    }

    func clearRecents() {
        recents = []
    }

    /// Remembers the names of debuggable apps for Shortcuts.
    func remember(_ apps: [DeviceOps.DeviceApp]) {
        var names: [String: String] = [:]
        for app in apps where app.debuggable { names[app.bundleID] = app.name }
        guard names != knownApps else { return }
        knownApps = names
        appsChanged()
    }

    /// Apps for Shortcuts: pinned, then recent, then the rest by name.
    var suggestions: [(bundleID: String, name: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for id in pinned where seen.insert(id).inserted { out.append((id, name(for: id))) }
        for recent in recents where seen.insert(recent.bundleID).inserted { out.append((recent.bundleID, recent.name)) }
        for (id, name) in knownApps.sorted(by: { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending })
        where seen.insert(id).inserted {
            out.append((id, name))
        }
        return out.map { (bundleID: $0.0, name: $0.1) }
    }

    // MARK: - Shortcuts and quick actions

    private func appsChanged() {
        updateQuickActions()
        AltLoadShortcuts.updateAppShortcutParameters()
    }

    /// The most recent app, then pinned ones, as Home Screen quick actions.
    func updateQuickActions() {
        var items: [UIApplicationShortcutItem] = []
        var seen = Set<String>()
        let ordered = recents.prefix(1).map { ($0.bundleID, $0.name) } + pinned.map { ($0, name(for: $0)) }
        for (id, name) in ordered where seen.insert(id).inserted && items.count < 3 {
            items.append(UIApplicationShortcutItem(
                type: Self.quickActionType,
                localizedTitle: name,
                localizedSubtitle: String(localized: "Open with JIT"),
                icon: UIApplicationShortcutIcon(systemImageName: "bolt.fill"),
                userInfo: ["bundleID": id as NSString]))
        }
        UIApplication.shared.shortcutItems = items
    }

    /// Runs a JIT quick action. Returns false for any other item.
    func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == Self.quickActionType,
              let bundleID = item.userInfo?["bundleID"] as? String, !bundleID.isEmpty else { return false }
        AppLog.shared.info(.jit, "Quick action: JIT for \(bundleID)")
        JITCenter.shared.start(bundleID: bundleID, appName: name(for: bundleID))
        return true
    }
}

// MARK: - Home Screen quick actions

/// Hands Home Screen quick actions to JITFavorites, at launch and while running.
final class AltLoadAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = AltLoadSceneDelegate.self
        if let item = options.shortcutItem {
            // Wait until the app is up before starting the session.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { _ = JITFavorites.shared.handle(item) }
            }
        }
        return config
    }
}

final class AltLoadSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let handled = MainActor.assumeIsolated { JITFavorites.shared.handle(shortcutItem) }
        completionHandler(handled)
    }
}
