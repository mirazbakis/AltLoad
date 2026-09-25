import SwiftUI

/// Creates a pairing file on-device (StikPair's mechanism) for this iPhone,
/// another iPhone/iPad, or an Apple TV.
struct PairView: View {
    @StateObject private var controller = PairingController.shared
    @StateObject private var store = PairingStore.shared
    @State private var appleTVPin = ""

    var body: some View {
        NavigationStack {
            AuroraScreen {
                header

                GlassEffectContainer(spacing: 18) {
                    content
                        .id(phaseKey)
                        .transition(.blurReplace.combined(with: .scale(0.96)))
                }
            }
            .navigationTitle("Pair")
            .toolbarTitleDisplayMode(.inlineLarge)
        }
        .animation(.spring(duration: 0.55, bounce: 0.25), value: controller.phase)
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
            GlassBadge(systemImage: headerSymbol, tint: headerTint, size: 100)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isWorking)

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
                GlassActionButton(title: "Pair This iPhone or iPad", systemImage: "iphone.gen3", prominent: true) {
                    controller.start()
                }
                GlassActionButton(title: "Pair Apple TV", systemImage: "appletv") {
                    controller.browseForAppleTVs()
                }

                if let latest = store.items.first {
                    lastPairingCard(latest)
                        .padding(.top, 8)
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
                footnote("If **Pair with AltLoad** doesn't show up, close the app and try again. No Live Activity? Turn on a background keep-alive in Settings.")
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
                    .glassEffect(.regular.tint(Aurora.indigo.opacity(0.3)).interactive(), in: .rect(cornerRadius: 22))
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
                .buttonStyle(.glassProminent)
                .tint(Aurora.violet)
                .controlSize(.extraLarge)

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

    // MARK: - Pieces

    private func lastPairingCard(_ item: SavedPairing) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Aurora.lilac)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last pairing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.displayName)
                        .font(.headline)
                    Text(item.date.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ShareLink(item: item.fileURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
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
        default: Aurora.violet
        }
    }

    private var subtitle: String {
        switch controller.phase {
        case .idle: "Create a pairing file right on this device. AltLoad uses it to install apps, just like a computer would."
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
