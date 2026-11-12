import SwiftUI

/// Full-screen install flow, SideStore style: sign in → download → LocalDevVPN →
/// sign & install → done. Presented over every tab by RootView, so Install and
/// refreshing an installed app share it.
struct InstallFlowView: View {
    let target: InstallTarget
    var onGoToPair: () -> Void = {}

    @ObservedObject private var controller = InstallController.shared
    @ObservedObject private var pairings = PairingStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var email = AppleIDStore.email
    @State private var password = ""
    @State private var remember = true
    @State private var openingWithJIT = false
    @State private var jitError: String?
    @AppStorage(ExtensionsMode.defaultsKey) private var extensionsRaw = ExtensionsMode.keep.rawValue
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 26) {
                        header
                        step
                            .id(phaseKey)
                            .transition(.blurReplace.combined(with: .scale(0.97)))
                    }
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    actions
                    .frame(maxWidth: 560)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CloseButton { controller.finish() }
                        .disabled(controller.isBusy)
                }
            }
        }
        .interactiveDismissDisabled()
        .fullScreenCover(item: $controller.twoFactor) { prompt in
            TwoFactorSheet(prompt: prompt) { controller.respond($0) }
                .auroraTheme()
        }
        .fullScreenCover(item: $controller.revoke) { prompt in
            RevokeSheet(prompt: prompt) { controller.respond($0) }
                .auroraTheme()
        }
        .onAppear {
            if password.isEmpty, !email.isEmpty, let saved = AppleIDStore.password(for: email) {
                password = saved
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from LocalDevVPN with the VPN on: carry on automatically.
            if phase == .active { controller.resumeWhenVPNReady() }
        }
        .animation(.spring(duration: 0.5, bounce: 0.2), value: controller.phase)
        .sensoryFeedback(trigger: controller.phase) { _, newPhase in
            switch newPhase {
            case .success: return .success
            case .failed: return .error
            default: return nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            AppIconView(url: iconURL, symbol: symbol, size: 104)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
            VStack(spacing: 4) {
                Text(target.title)
                    .font(.title.bold())
                    .foregroundStyle(Aurora.frost)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Aurora.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    private var iconURL: URL? {
        target.store.flatMap { controller.releases[$0]?.iconURL }
    }

    private var symbol: String {
        target.store?.fallbackSymbol ?? "doc.zipper"
    }

    private var subtitle: String {
        switch target {
        case .store(let store):
            if let release = controller.releases[store] {
                return String(localized: "Version \(release.version) · \(store.tagline)")
            }
            return store.tagline
        case .ipa:
            return String(localized: "Signed with your Apple ID")
        }
    }

    private var navigationTitle: String {
        switch controller.phase {
        case .success: String(localized: "Installed")
        case .failed: String(localized: "Install Failed")
        case .idle: actionVerb
        default: String(localized: "Installing")
        }
    }

    private var actionVerb: String {
        guard let store = target.store else { return String(localized: "Sign & Install") }
        guard controller.isOnDevice(store) else { return String(localized: "Install") }
        return controller.updateAvailable(store) ? String(localized: "Update") : String(localized: "Refresh")
    }

    // MARK: - Steps

    @ViewBuilder
    private var step: some View {
        switch controller.phase {
        case .idle:
            if pairings.selfPairing == nil {
                GlassCard(tint: Aurora.danger) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(localized: "Pair this iPhone first"), systemImage: "link.badge.plus")
                            .font(.headline)
                        Text("AltLoad needs this iPhone's pairing file to talk to it, the way a computer would.")
                            .font(.subheadline)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                }
            } else {
                signInForm
            }

        case .checking:
            stepsCard(detail: String(localized: "Getting ready…"))

        case .downloading:
            stepsCard(detail: String(localized: "Downloading \(target.title)…"))

        case .needsVPN:
            VStack(spacing: 16) {
                stepsCard(detail: nil)
                GlassCard(tint: Aurora.accent) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(String(localized: "Turn on LocalDevVPN"), systemImage: "network.badge.shield.half.filled")
                            .font(.headline)
                        Text("LocalDevVPN loops traffic for \(LocalDevVPN.targetIP) back into this iPhone, so AltLoad can reach it like a computer would. It only carries that one address, and your normal internet traffic isn't affected.")
                            .font(.subheadline)
                            .foregroundStyle(Aurora.secondaryText)
                        if !LocalDevVPN.isInstalled {
                            Text("It's free on the App Store. Install it, open it once to add the VPN configuration, then come back here.")
                                .font(.footnote)
                                .foregroundStyle(Aurora.secondaryText)
                        }
                    }
                }
            }

        case .working(let stage, _):
            stepsCard(detail: stage)

        case .success(let app):
            VStack(spacing: 18) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(app.name) \(app.version) is on your Home Screen")
                            .font(.headline)
                        if let duration = controller.lastInstallDuration {
                            let formatted = duration.formatted(.number.precision(.fractionLength(1)))
                            Label(String(localized: "Installed in \(formatted) seconds"), systemImage: "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Aurora.success)
                        }
                        if let expiration = app.expiration {
                            Text("Signed until \(expiration.formatted(date: .abbreviated, time: .shortened)). AltLoad reminds you the day before.")
                                .font(.subheadline)
                                .foregroundStyle(Aurora.secondaryText)
                        }
                        if app.store == .altstore || app.store == .altstoreBeta {
                            Label(String(localized: "AltStore uses AltLoad as its AltServer. Keep AltLoad open while AltStore installs or refreshes, or turn on background mode in Tools › AltServer."), systemImage: "server.rack")
                                .font(.footnote)
                                .foregroundStyle(Aurora.mist)
                        }
                        if app.store?.isSideStore == true {
                            Label(String(localized: "SideStore refreshes apps by itself. Keep LocalDevVPN on when it does."), systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote)
                                .foregroundStyle(Aurora.mist)
                        }
                        if app.store?.needsJIT == true {
                            Label(String(localized: "\(app.name) needs JIT to run. Open it with JIT here, or from Tools › JIT, each time."), systemImage: "bolt.fill")
                                .font(.footnote)
                                .foregroundStyle(Aurora.mist)
                        }
                        if let note = controller.pairingNote {
                            Label(note, systemImage: "doc.badge.gearshape")
                                .font(.footnote)
                                .foregroundStyle(Aurora.mist)
                        }
                        Text("First launch: if iOS says the developer isn't trusted, open **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**.")
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                }
            }

        case .failed(let message):
            VStack(spacing: 18) {
                GlassCard(tint: Aurora.danger) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "Stopped at: \(controller.step.title(for: target))"), systemImage: controller.step.symbol)
                            .font(.subheadline.weight(.semibold))
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// Progress bar over every step (LocalDevVPN, device link, sign in, sign, install…)
    /// with a checklist underneath.
    private func stepsCard(detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(controller.step.title(for: target))
                    .font(.headline)
                    .contentTransition(.opacity)
                Spacer()
                Text(controller.overallProgress.formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Aurora.secondaryText)
                    .contentTransition(.numericText())
            }

            GlassProgressBar(value: controller.overallProgress)

            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Aurora.secondaryText)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(controller.steps) { item in
                    stepRow(item)
                }
            }
            .padding(.top, 2)

            Text("Keep AltLoad open until this finishes.")
                .font(.caption)
                .foregroundStyle(Aurora.secondaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .animation(.spring(duration: 0.4), value: controller.step)
    }

    private func stepRow(_ item: InstallStep) -> some View {
        let current = controller.step
        let waitingForVPN = controller.phase == .needsVPN && item == .vpn
        return HStack(spacing: 12) {
            ZStack {
                if item < current {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Aurora.success)
                } else if item == current {
                    if waitingForVPN {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Aurora.sky)
                    } else {
                        ProgressRing(value: controller.stepFraction, lineWidth: 3, size: 20, showsPercent: false)
                    }
                } else {
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Aurora.secondaryText.opacity(0.6))
                }
            }
            .frame(width: 24, height: 24)

            Text(item.title(for: target))
                .font(.subheadline.weight(item == current ? .semibold : .regular))
                .foregroundStyle(item > current ? Aurora.secondaryText : Aurora.frost)
            Spacer(minLength: 0)
            if item == current, let fraction = controller.stepFraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Aurora.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Sign in

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Apple ID")
            VStack(spacing: 0) {
                TextField(String(localized: "Apple ID email"), text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .onChange(of: email) { _, value in
                        if let saved = AppleIDStore.password(for: value) { password = saved }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                Divider()
                    .overlay(Color.white.opacity(0.15))
                    .padding(.horizontal, 16)
                SecureField(String(localized: "Password"), text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(start)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                Divider()
                    .overlay(Color.white.opacity(0.15))
                    .padding(.horizontal, 16)
                Toggle(String(localized: "Remember password"), isOn: $remember)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
            }
            .cardSurface(radius: 18)

            extensionsPicker
                .padding(.top, 8)

            Text("Your password goes only to Apple, and a remembered one stays in this iPhone's Keychain. Apple also needs device-identity headers (\"anisette\"), which AltLoad gets from \(anisetteHost). \(limitNote)")
                .font(.system(size: 13))
                .foregroundStyle(Aurora.secondaryText)
                .padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var extensionsMode: ExtensionsMode {
        ExtensionsMode(rawValue: extensionsRaw) ?? .keep
    }

    /// SideStore's three choices for widgets and other extensions inside the app.
    private var extensionsPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "App Extensions")
            Menu {
                Picker(String(localized: "App Extensions"), selection: $extensionsRaw) {
                    ForEach(ExtensionsMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: extensionsMode.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Aurora.accent)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(extensionsMode.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Aurora.frost)
                        Text(extensionsMode.detail)
                            .font(.caption)
                            .foregroundStyle(Aurora.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Aurora.secondaryText)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .cardSurface(radius: 18)
        }
    }

    private var anisetteHost: String {
        if controller.anisetteURL == AnisetteServers.automatic { return String(localized: "a public server that's working right now") }
        return URL(string: controller.anisetteURL)?.host() ?? controller.anisetteURL
    }

    private var limitNote: String {
        String(localized: "With a free Apple ID apps last 7 days.")
    }

    private var canStart: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func start() {
        guard canStart else { return }
        focus = nil
        controller.install(
            with: AppleIDCredentials(email: email.trimmingCharacters(in: .whitespaces), password: password),
            remember: remember)
    }

    /// Opens a freshly installed emulator under the debugger, so it starts with JIT.
    private func openWithJIT(_ app: InstalledApp) {
        openingWithJIT = true
        Task {
            defer { openingWithJIT = false }
            do {
                try await DeviceOps.enableJIT(app.bundleID)
            } catch {
                jitError = error.localizedDescription
            }
        }
    }

    // MARK: - Bottom actions

    @ViewBuilder
    private var actions: some View {
        switch controller.phase {
        case .idle:
            if pairings.selfPairing == nil {
                GlassActionButton(title: "Go to Pair", systemImage: "antenna.radiowaves.left.and.right", prominent: true) {
                    controller.finish()
                    onGoToPair()
                }
            } else {
                GlassActionButton(title: LocalizedStringKey(actionVerb), systemImage: "signature", prominent: true, action: start)
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.55)
            }

        case .checking, .downloading, .working:
            GlassActionButton(title: "Cancel", systemImage: "xmark") { controller.cancel() }

        case .needsVPN:
            VStack(spacing: 12) {
                GlassActionButton(
                    title: LocalDevVPN.isInstalled ? "Turn On LocalDevVPN" : "Get LocalDevVPN",
                    systemImage: LocalDevVPN.isInstalled ? "power" : "arrow.down.app",
                    prominent: true
                ) {
                    LocalDevVPN.turnOn()
                }
                GlassActionButton(title: "It's On, Continue", systemImage: "arrow.right") {
                    controller.resumeAfterVPN(skipCheck: true)
                }
            }

        case .success(let app):
            VStack(spacing: 12) {
                if app.store?.needsJIT == true {
                    GlassActionButton(title: "Open with JIT", systemImage: "bolt.fill", prominent: true) {
                        openWithJIT(app)
                    }
                    .disabled(openingWithJIT)
                    .opacity(openingWithJIT ? 0.55 : 1)
                }
                GlassActionButton(title: "Done", systemImage: "checkmark", prominent: app.store?.needsJIT != true, tint: Aurora.success) {
                    controller.finish()
                }
            }
            .alert("Couldn't enable JIT", isPresented: Binding(get: { jitError != nil }, set: { if !$0 { jitError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(jitError ?? "")
            }

        case .failed:
            VStack(spacing: 12) {
                GlassActionButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                    controller.reset()
                }
                GlassActionButton(title: "Close") { controller.finish() }
            }
        }
    }

    private var phaseKey: String {
        switch controller.phase {
        case .idle: "idle"
        case .checking: "checking"
        case .downloading: "downloading"
        case .needsVPN: "vpn"
        case .working: "working"
        case .success: "success"
        case .failed: "failed"
        }
    }
}
