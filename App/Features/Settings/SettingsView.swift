import SwiftUI

/// Settings, opened from the gear at the top right of every tab.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pairing = PairingController.shared
    @StateObject private var install = InstallController.shared
    @StateObject private var anisette = AnisetteServers.shared
    @StateObject private var account = CertificatesController.shared
    @ObservedObject private var entitlements = EntitlementSettings.shared
    @State private var anisetteChoice = ""
    private static let customTag = "custom"
    @State private var appleID = AppleIDStore.email
    @State private var targetIP = LocalDevVPN.targetIP
    @State private var vpnActive = LocalDevVPN.isActive
    @State private var showSignIn = false
    @State private var anisetteReset = false
    @State private var sourceURLs: [StoreApp: String] = Dictionary(uniqueKeysWithValues: StoreApp.allCases.map {
        ($0, UserDefaults.standard.string(forKey: $0.sourceDefaultsKey) ?? $0.defaultSourceURL.absoluteString)
    })

    var body: some View {
        NavigationStack {
            AuroraScreen {
                appleIDCard
                LinkCard(title: "Entitlements", symbol: "checkmark.shield.fill",
                         value: entitlements.enabled.isEmpty ? "Off" : "\(entitlements.enabled.count) on") {
                    EntitlementsView()
                }
                anisetteCard
                vpnCard
                sourcesCard
                keepAliveCard
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                await anisette.refresh()
                syncAnisetteChoice()
            }
            .onAppear {
                syncAnisetteChoice()
                appleID = AppleIDStore.email
                vpnActive = LocalDevVPN.isActive
            }
            .onChange(of: account.phase) { _, _ in appleID = AppleIDStore.email }
            .fullScreenCover(isPresented: $showSignIn) {
                SignInSheet(anisetteURL: install.anisetteURL) { credentials, remember in
                    account.load(with: credentials, remember: remember)
                }
                .auroraTheme()
            }
            .fullScreenCover(item: $account.twoFactor) { prompt in
                TwoFactorSheet(prompt: prompt) { account.respond($0) }
                    .auroraTheme()
            }
        }
    }

    // MARK: - Apple ID

    private var appleIDCard: some View {
        CardSection(title: "Apple ID", symbol: "person.crop.circle.fill") {
            InfoRow(title: "Account", value: appleID.isEmpty ? "Not signed in" : appleID)
            accountStatus

            HStack(spacing: 10) {
                Button {
                    if let saved = account.savedCredentials {
                        account.load(with: saved)
                    } else {
                        showSignIn = true
                    }
                } label: {
                    Label(signInTitle, systemImage: "person.badge.key.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(AltLoadButtonStyle())
                .disabled(account.isBusy)

                Button(role: .destructive) {
                    AppleIDStore.forgetAll()
                    account.signOut()
                    appleID = ""
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(AltLoadButtonStyle(prominent: false, tint: Aurora.danger))
                .disabled(appleID.isEmpty)
                .accessibilityLabel("Forget Apple ID and password")
            }
            footnote("Signing in here checks your Apple ID with Apple straight away, including two-factor, without installing anything.")
        }
    }

    private var signInTitle: String {
        switch account.phase {
        case .loaded: "Check Again"
        case .loading: "Signing In…"
        default: appleID.isEmpty ? "Sign In" : "Sign In Again"
        }
    }

    @ViewBuilder
    private var accountStatus: some View {
        switch account.phase {
        case .signedOut:
            EmptyView()
        case .loading(let stage):
            HStack(spacing: 10) {
                ProgressView()
                Text(stage).font(.subheadline).foregroundStyle(Aurora.secondaryText)
            }
        case .loaded:
            Label("Signed in\(account.overview.map { " · \($0.team.name)" } ?? "")", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Aurora.success)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label("Sign-in failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Aurora.danger)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Aurora.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
        }
    }

    // MARK: - Anisette

    private var anisetteCard: some View {
        CardSection(title: "Anisette", symbol: "server.rack") {
            HStack {
                Text("Server").foregroundStyle(Aurora.secondaryText)
                if anisette.isLoading { ProgressView() }
                Spacer()
                Picker("Server", selection: $anisetteChoice) {
                    Text("Automatic").tag(AnisetteServers.automatic)
                    Divider()
                    ForEach(anisette.servers) { server in
                        Text(server.name).tag(server.address)
                    }
                    Text("Custom…").tag(Self.customTag)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            .font(.subheadline)
            .frame(minHeight: 44)
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
            } else if anisetteChoice != AnisetteServers.automatic {
                InfoRow(title: "Address", value: install.anisetteURL, monospaced: true)
            }

            Button {
                AnisetteServers.resetProvisioning()
                anisetteReset = true
            } label: {
                Label(anisetteReset ? "Anisette Data Reset" : "Reset Anisette Data",
                      systemImage: anisetteReset ? "checkmark" : "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AltLoadButtonStyle(prominent: false))
            .disabled(anisetteReset)

            footnote("Apple needs device-identity headers (\"anisette\") to sign in; the server never sees your password. Automatic checks which servers answer and moves on to the next one if Apple refuses a server's data. Reset if sign-in keeps failing.")
        }
    }

    // MARK: - LocalDevVPN

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
            .buttonStyle(AltLoadButtonStyle(prominent: false))
            footnote("Installs go through LocalDevVPN, which loops this address back into the iPhone. Only change it if you changed LocalDevVPN's peer IP.")
        }
    }

    // MARK: - Sources

    private var sourcesCard: some View {
        CardSection(title: "Sources", symbol: "shippingbox.fill") {
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
                Label("Use Official Sources", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
            .buttonStyle(AltLoadButtonStyle(prominent: false))
            footnote("AltLoad installs the newest build each source lists. If SideStore's source or repository is down, it falls back to a mirror, its GitHub releases and then a known-good build.")
        }
    }

    private var keepAliveCard: some View {
        CardSection(title: "Background Keep-Alive", symbol: "bolt.horizontal.circle.fill") {
            Toggle("Silent audio", systemImage: "speaker.wave.2", isOn: $pairing.keepAliveAudio)
                .frame(minHeight: 44)
            Toggle("Location", systemImage: "location", isOn: $pairing.keepAliveLocation)
                .frame(minHeight: 44)
            footnote("Turn one on if the Live Activity doesn't start while you pair from Settings.")
        }
    }

    // MARK: - Helpers

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Aurora.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func syncAnisetteChoice() {
        let current = install.anisetteURL
        if current == AnisetteServers.automatic || anisette.servers.contains(where: { $0.address == current }) {
            anisetteChoice = current
        } else {
            anisetteChoice = Self.customTag
        }
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
