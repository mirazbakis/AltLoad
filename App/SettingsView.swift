import SwiftUI

struct SettingsView: View {
    @StateObject private var pairing = PairingController.shared
    @StateObject private var install = InstallController.shared
    @StateObject private var anisette = AnisetteServers.shared
    @State private var anisetteChoice = ""
    private static let customTag = "custom"
    @State private var appleID = AppleIDStore.email
    @State private var targetIP = LocalDevVPN.targetIP
    @State private var vpnActive = LocalDevVPN.isActive
    @State private var sourceURL = UserDefaults.standard.string(forKey: "altstore.sourceURL")
        ?? AltStoreCatalog.defaultSourceURL.absoluteString

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "\(v) (\(b))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        AltLoadMark(size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("AltLoad")
                                .font(.title2.bold())
                                .foregroundStyle(Aurora.frost)
                            Text("Version \(version)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("AltStore, installed without a computer")
                                .font(.caption)
                                .foregroundStyle(Aurora.lilac.opacity(0.8))
                        }
                    }
                    .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)

                Section("Apple ID") {
                    LabeledContent("Account", value: appleID.isEmpty ? "Not signed in" : appleID)
                    Button("Forget Apple ID and Password", role: .destructive) {
                        AppleIDStore.forgetAll()
                        appleID = ""
                    }
                    .disabled(appleID.isEmpty)
                }
                .auroraRow()

                Section {
                    LabeledContent("Status", value: vpnActive ? "Connected" : "Not connected")
                    TextField("10.7.0.1", text: $targetIP)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .onChange(of: targetIP) { _, value in LocalDevVPN.targetIP = value }
                    Button(LocalDevVPN.isInstalled ? "Turn On LocalDevVPN" : "Get LocalDevVPN") {
                        LocalDevVPN.turnOn()
                    }
                } header: {
                    Text("LocalDevVPN")
                } footer: {
                    Text("Installs go through LocalDevVPN, which loops this address back into the iPhone. Only change it if you changed LocalDevVPN's peer IP.")
                }
                .auroraRow()

                Section {
                    Picker("Server", selection: $anisetteChoice) {
                        ForEach(anisette.servers) { server in
                            Text(server.name).tag(server.address)
                        }
                        Text("Custom…").tag(Self.customTag)
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: anisetteChoice) { _, choice in
                        if choice != Self.customTag { install.anisetteURL = choice }
                    }

                    if anisetteChoice == Self.customTag {
                        TextField("https://…", text: $install.anisetteURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        LabeledContent("Address") {
                            Text(install.anisetteURL)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Anisette server")
                        if anisette.isLoading { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    Text("Apple requires device-identity headers (\"anisette\") to sign in. The server never sees your password. If sign-in fails, try another server. The list comes from SideStore's community servers.")
                }
                .auroraRow()

                Section {
                    TextField("https://…", text: $sourceURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveSource)
                    Button("Use Official Source") {
                        sourceURL = AltStoreCatalog.defaultSourceURL.absoluteString
                        saveSource()
                    }
                } header: {
                    Text("AltStore source")
                } footer: {
                    Text("AltLoad installs the newest AltStore listed in this source.")
                }
                .auroraRow()

                Section {
                    Toggle("Silent audio", systemImage: "speaker.wave.2", isOn: $pairing.keepAliveAudio)
                    Toggle("Location", systemImage: "location", isOn: $pairing.keepAliveLocation)
                } header: {
                    Text("Background keep-alive")
                } footer: {
                    Text("Turn one on if the Live Activity doesn't start while you pair from Settings.")
                }
                .auroraRow()

                Section {
                    LabeledContent("Version", value: version)
                    Link("idevice by jkcoxson", destination: URL(string: "https://github.com/jkcoxson/idevice")!)
                    Link("isideload by nab138", destination: URL(string: "https://github.com/nab138/isideload")!)
                    Link("StikPair by StephenDev0", destination: URL(string: "https://github.com/StephenDev0/StikPair")!)
                    Link("LocalDevVPN", destination: URL(string: "https://github.com/jkcoxson/LocalDevVPN")!)
                } header: {
                    Text("About")
                } footer: {
                    Text("AltLoad isn't affiliated with AltStore, Riley Testut or Apple. Pairing flow based on StikPair.")
                }
                .auroraRow()

                Section("Legal") {
                    Link("Terms of Service", destination: URL(string: "https://mirazbakis.github.io/terms.html")!)
                    Link("AltLoad License", destination: URL(string: "https://github.com/mirazbakis/AltLoad/blob/main/LICENSE")!)
                    Link("Third-Party Notices", destination: URL(string: "https://github.com/mirazbakis/AltLoad/blob/main/THIRD_PARTY_NOTICES.md")!)
                    Link("Security Policy", destination: URL(string: "https://github.com/mirazbakis/AltLoad/blob/main/SECURITY.md")!)
                }
                .auroraRow()
            }
            .auroraListBackground()
            .navigationTitle("Settings")
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

    private func syncAnisetteChoice() {
        anisetteChoice = anisette.servers.contains { $0.address == install.anisetteURL }
            ? install.anisetteURL : Self.customTag
    }

    private func saveSource() {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespaces)
        if trimmed == AltStoreCatalog.defaultSourceURL.absoluteString || trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: "altstore.sourceURL")
        } else {
            UserDefaults.standard.set(trimmed, forKey: "altstore.sourceURL")
        }
        Task { await install.loadCatalog() }
    }
}
