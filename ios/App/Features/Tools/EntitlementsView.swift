import SwiftUI

/// Tools › Entitlements: capabilities enabled on an app's App ID before it's
/// signed. One set for every app, and an own set for any installed app.
struct EntitlementsView: View {
    @ObservedObject private var settings = EntitlementSettings.shared
    @ObservedObject private var install = InstallController.shared
    @ObservedObject private var teams = TeamSettings.shared

    /// nil: the shared set.
    @State private var scope: String?
    @State private var search = ""

    private var selectedApp: InstalledApp? {
        scope.flatMap { id in install.apps.first { $0.bundleID == id } }
    }

    /// The Apple ID the selected app (or the default one) signs with.
    private var appleID: String { selectedApp?.appleID ?? AppleIDStore.email }
    private var team: DevTeam? { teams.effectiveTeam(for: appleID) }
    private var freeTeam: Bool { team?.isFree ?? false }

    /// The app has no own set, so its switches show the shared one, read-only.
    private var readOnly: Bool { scope.map { !settings.hasOwnSet($0) } ?? false }

    var body: some View {
        AuroraScreen {
            Text("Switched-on entitlements are enabled on the app's App ID with your Apple ID, then added to its signature the next time you install or refresh it.")
                .font(.footnote)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            scopeCard
            teamCard

            if search.isEmpty {
                presetsCard
            }

            let free = matching(.free)
            if !free.isEmpty {
                CardSection(title: "Free Apple ID", symbol: "person") {
                    ForEach(free) { row($0) }
                    note(String(localized: "Personal teams can usually enable these."))
                }
            }

            let paid = matching(.paid)
            if !paid.isEmpty {
                CardSection(title: "Paid Developer Account", symbol: "star", tint: Aurora.ember) {
                    ForEach(paid) { row($0) }
                    note(freeTeam
                         ? String(localized: "Your team is a free personal team, so AltLoad leaves these out when it signs.")
                         : String(localized: "These need an Apple Developer Program membership. On a free Apple ID, Apple refuses them and the install stops with the reason, so leave them off there."))
                }
            }

            if matching(.free).isEmpty && matching(.paid).isEmpty {
                GlassCard {
                    Text("No capability matches.")
                        .font(.subheadline)
                        .foregroundStyle(Aurora.secondaryText)
                }
            }

            if let app = selectedApp {
                grantedCard(app)
            }

            Button(role: .destructive) {
                settings.clear(for: scope)
            } label: {
                Label(String(localized: "Turn All Off"), systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(AltLoadButtonStyle(prominent: false, tint: Aurora.danger))
            .disabled(readOnly || settings.set(for: scope).isEmpty)

            note(String(localized: "Turning one off stops AltLoad asking for it. Apple keeps it on the App ID until you remove it at developer.apple.com, so the profile may still include it."))
                .multilineTextAlignment(.center)
        }
        .navigationTitle(String(localized: "Entitlements"))
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: String(localized: "Search entitlements"))
        .onAppear {
            settings.prune(keeping: Set(install.apps.map(\.bundleID)))
            if let scope, !install.apps.contains(where: { $0.bundleID == scope }) { self.scope = nil }
        }
    }

    // MARK: - Cards

    private var scopeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Apply to").font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker(String(localized: "Apply to"), selection: $scope) {
                        Text("All apps").tag(String?.none)
                        ForEach(install.apps) { app in
                            Text(app.name).tag(String?.some(app.bundleID))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Aurora.sky)
                }
                if let app = selectedApp {
                    Toggle(String(localized: "Own set for \(app.name)"), isOn: Binding(
                        get: { settings.hasOwnSet(app.bundleID) },
                        set: { settings.setUsesOwn($0, for: app.bundleID) }))
                        .font(.subheadline)
                    note(settings.hasOwnSet(app.bundleID)
                         ? String(localized: "Only this app uses these switches. Used on its next refresh.")
                         : String(localized: "This app uses the set for all apps. Turn on Own set to change it for this app only."))
                } else {
                    let own = install.apps.filter { settings.hasOwnSet($0.bundleID) }
                    note(own.isEmpty
                         ? String(localized: "Every app uses this set. Pick an installed app to give it its own.")
                         : String(localized: "Used by every app except \(own.map(\.name).joined(separator: ", ")), which have their own."))
                }
            }
        }
    }

    @ViewBuilder
    private var teamCard: some View {
        if let team {
            GlassCard(tint: freeTeam && settings.hasPaid(for: scope) ? Aurora.ember : nil) {
                HStack(spacing: 12) {
                    IconTile(symbol: freeTeam ? "person.crop.circle" : "star.circle", tint: freeTeam ? Aurora.mist : Aurora.ember, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.displayName).font(.subheadline.weight(.semibold))
                        Text(freeTeam && settings.hasPaid(for: scope)
                             ? String(localized: "\(team.kindTitle) · paid entitlements below are skipped")
                             : team.kindTitle)
                            .font(.caption)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var presetsCard: some View {
        CardSection(title: "Presets", symbol: "square.stack") {
            ForEach(CapabilityPreset.all) { preset in
                Button {
                    settings.apply(preset, for: scope)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: preset.symbol).foregroundStyle(Aurora.sky).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).foregroundStyle(Aurora.frost)
                            Text(preset.detail).font(.caption).foregroundStyle(Aurora.secondaryText)
                        }
                        Spacer(minLength: 0)
                        if Set(preset.capabilities).isSubset(of: settings.set(for: scope)) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Aurora.success)
                        } else {
                            Image(systemName: "plus.circle").foregroundStyle(Aurora.sky)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(readOnly)
            }
            note(String(localized: "A preset switches its entitlements on. It doesn't turn others off."))
        }
    }

    /// What the profile from the app's last signing actually granted.
    private func grantedCard(_ app: InstalledApp) -> some View {
        CardSection(title: "Last signed profile", symbol: "doc.text.magnifyingglass") {
            if let granted = app.grantedEntitlements {
                let requested = Capability.all.filter { settings.set(for: app.bundleID).contains($0.id) }
                let missing = requested.filter { cap in cap.entitlement.map { !granted.contains($0) } ?? false }
                if !missing.isEmpty {
                    note(String(localized: "Switched on but not in the profile yet: \(missing.map(\.name).joined(separator: ", ")). Refresh the app to ask again."))
                        .foregroundStyle(Aurora.ember)
                }
                ForEach(granted, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Capability.all.first { $0.entitlement == key }?.name ?? key)
                            .font(.subheadline)
                        if Capability.all.contains(where: { $0.entitlement == key }) {
                            Text(key).font(.caption2.monospaced()).foregroundStyle(Aurora.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                note(String(localized: "Signed \(app.installedAt.formatted(date: .abbreviated, time: .shortened))\(app.teamName.map { " · \($0)" } ?? "")"))
            } else {
                note(String(localized: "Shown after the app is installed or refreshed with this version of AltLoad."))
            }
        }
    }

    // MARK: - Pieces

    private func matching(_ tier: Capability.Tier) -> [Capability] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return Capability.all.filter { cap in
            cap.tier == tier && (query.isEmpty
                || cap.name.localizedCaseInsensitiveContains(query)
                || cap.detail.localizedCaseInsensitiveContains(query)
                || cap.id.localizedCaseInsensitiveContains(query)
                || (cap.entitlement?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Aurora.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ capability: Capability) -> some View {
        let on = settings.set(for: scope).contains(capability.id)
        // On a free team a paid one can still be switched off, not on.
        let blocked = capability.tier == .paid && freeTeam && !on
        return Toggle(isOn: settings.binding(capability, for: scope)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(capability.name)
                        if capability.tier == .paid {
                            Text("Paid")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Aurora.ember)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Aurora.ember.opacity(0.15), in: .capsule)
                        }
                    }
                    Text(capability.tier == .paid && freeTeam && on
                         ? String(localized: "Skipped: your team is a free personal team")
                         : capability.detail)
                        .font(.caption)
                        .foregroundStyle(capability.tier == .paid && freeTeam && on ? Aurora.ember : Aurora.secondaryText)
                }
            } icon: {
                Image(systemName: capability.symbol)
                    .foregroundStyle(capability.tier == .paid ? Aurora.ember : Aurora.sky)
            }
        }
        .disabled(readOnly || blocked)
        .opacity(blocked ? 0.5 : 1)
    }
}

#Preview {
    NavigationStack { EntitlementsView() }
        .auroraTheme()
}
