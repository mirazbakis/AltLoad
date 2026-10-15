import SwiftUI

/// Settings as glass cards on the midnight background.
struct SettingsView: View {
    @StateObject private var pairing = PairingController.shared
    @StateObject private var install = InstallController.shared
    @StateObject private var anisette = AnisetteServers.shared
    @ObservedObject private var altServer = AltServerHost.shared
    @ObservedObject private var entitlements = EntitlementSettings.shared
    @State private var anisetteChoice = ""
    private static let customTag = "custom"
    @State private var appleID = AppleIDStore.email
    @State private var targetIP = LocalDevVPN.targetIP
    @State private var vpnActive = LocalDevVPN.isActive
    @State private var sourceURLs: [StoreApp: String] = Dictionary(uniqueKeysWithValues: StoreApp.allCases.map {
        ($0, UserDefaults.standard.string(forKey: $0.sourceDefaultsKey) ?? $0.defaultSourceURL.absoluteString)
    })

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            AuroraScreen {
                headerCard
                appleIDCard
                LinkCard(title: "Entitlements", symbol: "checkmark.shield.fill",
                         value: entitlements.enabled.isEmpty ? "Off" : "\(entitlements.enabled.count) on") {
                    EntitlementsView()
                }
                vpnCard
                anisetteCard
                sourcesCard
                keepAliveCard
                thanksCard
                legalCard

                Text("AltLoad isn't affiliated with AltStore, Riley Testut or Apple. Apple, iPhone and iOS are trademarks of Apple Inc.")
                    .font(.caption)
                    .foregroundStyle(Aurora.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("Settings")
            .toolbarTitleDisplayMode(.inlineLarge)
            .task {
                await anisette.refresh()
                syncAnisetteChoice()
            }
            .onAppear {
                syncAnisetteChoice()
                appleID = AppleIDStore.email
                vpnActive = LocalDevVPN.isActive
            }
        }
    }

    // MARK: - Cards

    private var headerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    AltLoadMark(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AltLoad")
                            .font(.title2.bold())
                            .foregroundStyle(Aurora.frost)
                        Text("Version \(version)")
                            .font(.subheadline)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    StatTile(title: "Apps", value: "\(install.apps.count)")
                    StatTile(title: "Entitlements", value: "\(entitlements.enabled.count)")
                    StatTile(title: "AltServer", value: altServer.isRunning ? "On" : "Off")
                }
            }
        }
    }

    private var appleIDCard: some View {
        CardSection(title: "Apple ID", symbol: "person.crop.circle.fill") {
            InfoRow(title: "Account", value: appleID.isEmpty ? "Not signed in" : appleID)
            Button(role: .destructive) {
                AppleIDStore.forgetAll()
                appleID = ""
            } label: {
                Label("Forget Apple ID and Password", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(appleID.isEmpty)
        }
    }

    private var vpnCard: some View {
        CardSection(title: "LocalDevVPN", symbol: "network.badge.shield.half.filled") {
            InfoRow(title: "Status", value: vpnActive ? "Connected" : "Not connected")
            TextField("10.7.0.1", text: $targetIP)
                .font(.subheadline.monospaced())
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .inputField()
                .onChange(of: targetIP) { _, value in LocalDevVPN.targetIP = value }
            Button {
                LocalDevVPN.turnOn()
            } label: {
                Label(LocalDevVPN.isInstalled ? "Turn On LocalDevVPN" : "Get LocalDevVPN", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            footnote("Installs go through LocalDevVPN, which loops this address back into the iPhone. Only change it if you changed LocalDevVPN's peer IP.")
        }
    }

    private var anisetteCard: some View {
        CardSection(title: "Anisette Server", symbol: "server.rack") {
            HStack {
                Text("Server").foregroundStyle(Aurora.secondaryText)
                if anisette.isLoading { ProgressView().controlSize(.mini) }
                Spacer()
                Picker("Server", selection: $anisetteChoice) {
                    ForEach(anisette.servers) { server in
                        Text(server.name).tag(server.address)
                    }
                    Text("Custom…").tag(Self.customTag)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .font(.subheadline)
            .onChange(of: anisetteChoice) { _, choice in
                if choice != Self.customTag { install.anisetteURL = choice }
            }

            if anisetteChoice == Self.customTag {
                TextField("https://…", text: $install.anisetteURL)
                    .font(.footnote.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .inputField()
            } else {
                InfoRow(title: "Address", value: install.anisetteURL, monospaced: true)
            }
            footnote("Apple requires device-identity headers (\"anisette\") to sign in. The server never sees your password. If sign-in fails, try another server.")
        }
    }

    private var sourcesCard: some View {
        CardSection(title: "AltStore Sources", symbol: "shippingbox.fill") {
            ForEach(StoreApp.allCases) { store in
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Aurora.secondaryText)
                    TextField("https://…", text: sourceBinding(store))
                        .font(.footnote.monospaced())
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .inputField()
                        .onSubmit { saveSource(store) }
                }
            }
            Button {
                for store in StoreApp.allCases {
                    sourceURLs[store] = store.defaultSourceURL.absoluteString
                    saveSource(store)
                }
            } label: {
                Label("Use Official Source", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            footnote("AltLoad installs the newest version listed in each source. Pick Release or Beta on the Install tab.")
        }
    }

    private var keepAliveCard: some View {
        CardSection(title: "Background Keep-Alive", symbol: "bolt.horizontal.circle.fill") {
            Toggle("Silent audio", systemImage: "speaker.wave.2", isOn: $pairing.keepAliveAudio)
            Toggle("Location", systemImage: "location", isOn: $pairing.keepAliveLocation)
            footnote("Turn one on if the Live Activity doesn't start while you pair from Settings.")
        }
    }

    private var thanksCard: some View {
        CardSection(title: "Special Thanks", symbol: "heart.fill") {
            thanksRow("jkcoxson", for: "idevice and LocalDevVPN, which let AltLoad talk to this iPhone", url: "https://github.com/jkcoxson")
            thanksRow("nab138", for: "isideload: Apple ID sign-in, signing and installing", url: "https://github.com/nab138/isideload")
            thanksRow("StephenDev0", for: "StikPair and StikDebug, the base for pairing and JIT", url: "https://github.com/StephenDev0")
            thanksRow("Riley Testut", for: "AltStore", url: "https://github.com/altstoreio/AltStore")
        }
    }

    private var legalCard: some View {
        CardSection(title: "Legal", symbol: "doc.text.fill") {
            linkRow("Terms of Service", "https://mirazbakis.github.io/terms.html")
            linkRow("AltLoad License", "https://github.com/mirazbakis/AltLoad/blob/main/LICENSE")
            linkRow("Third-Party Notices", "https://github.com/mirazbakis/AltLoad/blob/main/THIRD_PARTY_NOTICES.md")
            linkRow("Security Policy", "https://github.com/mirazbakis/AltLoad/blob/main/SECURITY.md")
        }
    }

    // MARK: - Rows

    private func thanksRow(_ name: String, for work: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Aurora.sky)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Aurora.frost)
                    Text(work).font(.caption).foregroundStyle(Aurora.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Aurora.secondaryText)
            }
        }
    }

    private func linkRow(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Aurora.frost)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Aurora.secondaryText)
            }
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Aurora.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Helpers

    private func syncAnisetteChoice() {
        anisetteChoice = anisette.servers.contains { $0.address == install.anisetteURL }
            ? install.anisetteURL : Self.customTag
    }

    private func sourceBinding(_ store: StoreApp) -> Binding<String> {
        Binding(get: { sourceURLs[store] ?? "" }, set: { sourceURLs[store] = $0 })
    }

    private func saveSource(_ store: StoreApp) {
        let trimmed = (sourceURLs[store] ?? "").trimmingCharacters(in: .whitespaces)
        if trimmed == store.defaultSourceURL.absoluteString || trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: store.sourceDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: store.sourceDefaultsKey)
        }
        Task { await install.loadCatalog(store) }
    }
}
