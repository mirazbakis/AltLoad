import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

/// Creates a pairing file on-device (StikPair's mechanism) for this iPhone,
/// another iPhone/iPad, or an Apple TV.
struct PairView: View {
    @StateObject private var controller = PairingController.shared
    @StateObject private var store = PairingStore.shared
    @State private var appleTVPin = ""
    @State private var showImporter = false

    var body: some View {
        AuroraScreen {
            header

            GlassGroup(spacing: 18) {
                content
                    .id(phaseKey)
                    .transition(.blurReplace.combined(with: .scale(0.96)))
            }
        }
        .navigationTitle("Pair")
        .toolbarTitleDisplayMode(.inlineLarge)
        .animation(.spring(duration: 0.55, bounce: 0.25), value: controller.phase)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.propertyList, .xml, .data]) { result in
            guard case .success(let url) = result else { return }
            do {
                controller.phase = .success(try store.importForThisDevice(at: url))
            } catch {
                controller.phase = .failed("The pairing file couldn't be imported: \(error.localizedDescription)")
            }
        }
        .sensoryFeedback(trigger: controller.phase) { _, newPhase in
            switch newPhase {
            case .success: return .success
            case .failed: return .error
            case .showPin, .enteringAppleTVPin: return .impact(weight: .medium)
            default: return nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Group {
                if case .idle = controller.phase {
                    AltLoadMark(size: 100)
                } else {
                    GlassBadge(systemImage: headerSymbol, tint: headerTint, size: 100)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, isActive: isWorking)
                }
            }
            .padding(.vertical, 6)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
        .padding(.top, 4)
    }

    // MARK: - Phase content

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .idle:
            VStack(spacing: 14) {
                if PairingController.canPairOnDevice {
                    GlassActionButton(title: "Pair This iPhone or iPad", systemImage: "iphone.gen3", prominent: true) {
                        controller.start()
                    }
                    GlassActionButton(title: "Import Pairing File", systemImage: "square.and.arrow.down") {
                        showImporter = true
                    }
                } else {
                    importGuidance
                    GlassActionButton(title: "Import Pairing File", systemImage: "square.and.arrow.down", prominent: true) {
                        showImporter = true
                    }
                }
                GlassActionButton(title: "Pair Apple TV", systemImage: "appletv") {
                    controller.browseForAppleTVs()
                }

                if !store.items.isEmpty {
                    VStack(spacing: 10) {
                        SectionLabel(title: "Pairing files", trailing: "\(store.items.count)")
                        ForEach(store.items) { item in
                            lastPairingCard(item)
                                .contextMenu {
                                    if !item.isAppleTV {
                                        Button("Use for Installs on This iPhone", systemImage: "iphone.gen3") {
                                            store.selfPairingID = item.id
                                        }
                                    }
                                    ShareLink(item: item.fileURL)
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        store.delete(item)
                                    }
                                }
                        }
                        Text("The file marked **This iPhone** is used for installs. Long-press a file to change it or delete it. Files also appear in **Files › On My iPhone › AltLoad**.")
                            .font(.caption)
                            .foregroundStyle(Aurora.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    .padding(.top, 10)
                }
            }

        case .waiting:
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Waiting for a device to connect…")
                                .foregroundStyle(.secondary)
                        }
                        Text("On this iPhone:")
                            .font(.subheadline.weight(.semibold))
                        GuideStep(number: 1, text: "Open the **Settings** app")
                        GuideStep(number: 2, text: "Go to **Privacy & Security**")
                        GuideStep(number: 3, text: "Tap **Developer Mode**")
                        GuideStep(number: 4, text: "Scroll down and tap **Pair with AltLoad**")
                    }
                }
                locationGuidance
                footnote("If **Pair with AltLoad** doesn't show up, close the app and try again.")
            }

        case .showPin(let pin):
            VStack(spacing: 18) {
                Text("Enter this code on your device")
                    .font(.headline)
                GlassCodeView(code: pin)
                ProgressView()
            }

        case .browsingAppleTV:
            VStack(spacing: 14) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("On your Apple TV:")
                            .font(.subheadline.weight(.semibold))
                        GuideStep(number: 1, text: "Open **Settings › Remotes and Devices**")
                        GuideStep(number: 2, text: "Choose **Remote App and Devices**")
                    }
                }

                if controller.appleTVs.isEmpty {
                    ProgressView("Looking for Apple TVs…")
                        .padding(.vertical, 8)
                } else {
                    ForEach(controller.appleTVs) { device in
                        GlassActionButton(title: LocalizedStringKey(device.name), systemImage: "appletv", prominent: true) {
                            appleTVPin = ""
                            controller.pairAppleTV(device)
                        }
                    }
                }

                GlassActionButton(title: "Cancel") { controller.cancelAppleTVPairing() }
            }

        case .enteringAppleTVPin(let device):
            VStack(spacing: 16) {
                Text("Pair with \(device.name)")
                    .font(.headline)
                Text("Enter the six-digit code shown on your Apple TV.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                TextField("000000", text: $appleTVPin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .tracking(6)
                    .onChange(of: appleTVPin) { _, value in
                        appleTVPin = String(value.filter(\.isNumber).prefix(6))
                    }
                    .padding(.vertical, 14)
                    .cardSurface()
                GlassActionButton(title: "Pair", systemImage: "link", prominent: true) {
                    controller.submitAppleTVPin(appleTVPin)
                }
                .disabled(appleTVPin.count != 6)
                GlassActionButton(title: "Cancel") { controller.cancelAppleTVPairing() }
            }

        case .pairingAppleTV(let name):
            VStack(spacing: 16) {
                GlassCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Pairing with \(name)…")
                            .foregroundStyle(.secondary)
                    }
                }
                GlassActionButton(title: "Cancel") { controller.cancelAppleTVPairing() }
            }

        case .success(let saved):
            VStack(spacing: 14) {
                GlassCard(tint: Aurora.success) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Paired", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold())
                            .foregroundStyle(Aurora.success)
                        detailRow("Device", saved.displayName)
                        if !saved.model.isEmpty { detailRow("Model", saved.model) }
                        if !saved.udid.isEmpty { detailRow("Pairing ID", saved.udid, monospaced: true) }
                    }
                }

                ShareLink(item: saved.fileURL) {
                    Label("Export Pairing File", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundStyle(Aurora.frost)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(AltLoadButtonStyle(minHeight: 56))

                footnote(saved.isAppleTV
                         ? "Also saved in **Files › On My iPhone › AltLoad › Pairings**."
                         : "AltLoad will use this file for installs. It's also in **Files › On My iPhone › AltLoad › Pairings**.")

                GlassActionButton(title: "Done") { controller.reset() }
            }

        case .failed(let message):
            VStack(spacing: 14) {
                GlassCard(tint: Aurora.danger) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Pairing failed", systemImage: "xmark.octagon.fill")
                            .font(.title3.bold())
                            .foregroundStyle(Aurora.danger)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                GlassActionButton(title: "Try Again", systemImage: "arrow.clockwise", prominent: true) {
                    controller.reset()
                }
            }
        }
    }

    /// Tells the user which Location button to tap so AltLoad keeps running in
    /// the background while they're in Settings — no need to enable anything there.
    @ViewBuilder
    private var locationGuidance: some View {
        switch controller.locationAuthorization {
        case .notDetermined:
            GlassCard(tint: Aurora.accent) {
                HStack(spacing: 12) {
                    Image(systemName: "location.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Aurora.accent)
                    Text("When iOS asks, tap **Allow While Using App** so pairing keeps running while you're in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .authorizedWhenInUse:
            GlassCard(tint: Aurora.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("For the most reliable pairing, allow location **Always**.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Allow Always") { controller.requestLocationAuthorization() }
                        .buttonStyle(AltLoadButtonStyle(prominent: false, radius: 14, minHeight: 44))
                }
            }
        case .denied, .restricted:
            GlassCard(tint: Aurora.danger) {
                Text("Location is off, so background keep-alive can't run. If **Pair with AltLoad** doesn't appear, turn on **Silent audio** in Settings, or allow Location for AltLoad.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    /// Below iOS 27 the iPhone can't pair with AltLoad, so the pairing file has
    /// to come from a computer once.
    private var importGuidance: some View {
        GlassCard(tint: Aurora.accent) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Import a pairing file", systemImage: "doc.badge.gearshape")
                    .font(.headline)
                    .foregroundStyle(Aurora.frost)
                Text("Pairing on this device needs iOS 27. On iOS \(UIDevice.current.systemVersion), make a pairing file on a computer once, then bring it here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                GuideStep(number: 1, text: "Create the pairing file on a Mac or PC, for example with **iloader** or **idevice_pair**")
                GuideStep(number: 2, text: "Save it to **Files** on this iPhone or iPad, or AirDrop it over")
                GuideStep(number: 3, text: "Tap **Import Pairing File** and choose it")
            }
        }
    }

    // MARK: - Pieces

    private func lastPairingCard(_ item: SavedPairing) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: item.isAppleTV ? "appletv" : "iphone.gen3")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Aurora.mist)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.displayName)
                            .font(.headline)
                        if store.selfPairing?.id == item.id {
                            Text("This iPhone")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Aurora.frost)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Aurora.accentDeep, in: .capsule)
                        }
                    }
                    Text(item.date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ShareLink(item: item.fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Aurora.frost)
                        .frame(width: 44, height: 44)
                        .background(Aurora.raised, in: .circle)
                        .overlay { Circle().strokeBorder(Aurora.hairline, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Export \(item.displayName) pairing file")
            }
        }
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .body)
                .textSelection(.enabled)
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Phase-driven styling

    private var phaseKey: String {
        switch controller.phase {
        case .idle: "idle"
        case .waiting: "waiting"
        case .showPin: "pin"
        case .browsingAppleTV: "browse"
        case .enteringAppleTVPin: "tvpin"
        case .pairingAppleTV: "tvpairing"
        case .success: "success"
        case .failed: "failed"
        }
    }

    private var isWorking: Bool {
        switch controller.phase {
        case .waiting, .browsingAppleTV, .pairingAppleTV: true
        default: false
        }
    }

    private var headerSymbol: String {
        switch controller.phase {
        case .idle: "antenna.radiowaves.left.and.right"
        case .waiting: "wifi"
        case .showPin, .enteringAppleTVPin: "lock.open"
        case .browsingAppleTV, .pairingAppleTV: "appletv"
        case .success: "checkmark"
        case .failed: "xmark"
        }
    }

    private var headerTint: Color {
        switch controller.phase {
        case .success: Aurora.success
        case .failed: Aurora.danger
        default: Aurora.accent
        }
    }

    private var subtitle: String {
        switch controller.phase {
        case .idle: PairingController.canPairOnDevice
            ? "Create a pairing file right on this device. AltLoad uses it to install apps, just like a computer would."
            : "AltLoad needs this device's pairing file to install apps, just like a computer would."
        case .waiting: "Listening on your local network."
        case .showPin, .enteringAppleTVPin: "Almost there."
        case .browsingAppleTV: "Searching nearby."
        case .pairingAppleTV: "Hang tight."
        case .success: "Your pairing file is ready."
        case .failed: "Something went wrong."
        }
    }
}

#Preview {
    PairView()
        .auroraTheme()
}
