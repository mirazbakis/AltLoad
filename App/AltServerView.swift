import SwiftUI

/// Status and settings for AltLoad's on-device AltServer.
struct AltServerView: View {
    @ObservedObject private var host = AltServerHost.shared
    @ObservedObject private var pairings = PairingStore.shared
    @State private var vpnActive = LocalDevVPN.isActive
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AuroraScreen {
            header

            if let activity = host.activity {
                GlassCard(tint: Aurora.violet) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(activity.title).font(.headline)
                        GlassProgressBar(value: activity.fraction ?? 0)
                            .opacity(activity.fraction == nil ? 0.5 : 1)
                        Text(activity.stage)
                            .font(.footnote)
                            .foregroundStyle(Aurora.secondaryText)
                    }
                }
                .transition(.blurReplace)
            }

            VStack(spacing: 10) {
                SectionLabel(title: "Server")
                VStack(spacing: 0) {
                    Toggle(isOn: $host.isEnabled) {
                        Label("AltServer", systemImage: "server.rack")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    Divider().overlay(Color.white.opacity(0.15)).padding(.horizontal, 16)
                    Toggle(isOn: $host.keepAwake) {
                        Label("Keep running in background", systemImage: "speaker.wave.2")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .disabled(!host.isEnabled)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                }
                .glassEffect(.regular.tint(Aurora.card.opacity(0.6)), in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Aurora.hairline, lineWidth: 1)
                }
                Text("iOS pauses apps in the background. Keep AltLoad open while AltStore installs or refreshes, or turn on background mode (it plays inaudible audio).")
                    .font(.system(size: 13))
                    .foregroundStyle(Aurora.secondaryText)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 10) {
                SectionLabel(title: "How AltStore finds it")
                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        StatusRow(
                            title: "On-device link",
                            detail: host.isRunning
                                ? "Answers AltStore's USB-style server check on this iPhone. AltStore prefers this one."
                                : "Off",
                            state: host.isRunning ? .done : .pending)
                        StatusRow(
                            title: "Wi-Fi (Bonjour)",
                            detail: host.wifiState == "Advertising"
                                ? "Advertised as AltLoad with AltStore's server ID"
                                : host.wifiState,
                            state: host.wifiState == "Advertising" ? .done : .pending)
                        StatusRow(
                            title: "Pairing file",
                            detail: pairings.selfPairing?.displayName ?? "Needed. Create one in Tools › Pair",
                            state: pairings.selfPairing == nil ? .attention : .done)
                        StatusRow(
                            title: "LocalDevVPN",
                            detail: vpnActive ? "Connected" : "Turn it on before refreshing in AltStore",
                            state: vpnActive ? .done : .attention)
                    }
                }
            }

            VStack(spacing: 10) {
                SectionLabel(title: "Activity", trailing: host.events.isEmpty ? nil : "\(host.events.count)")
                GlassCard {
                    if host.events.isEmpty {
                        Text("Nothing yet. Open AltStore and refresh an app.")
                            .font(.subheadline)
                            .foregroundStyle(Aurora.secondaryText)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(host.events) { event in
                                eventRow(event)
                            }
                        }
                    }
                }
                if !host.events.isEmpty {
                    Button("Clear Activity") { host.clearLog() }
                        .font(.footnote)
                        .foregroundStyle(Aurora.secondaryText)
                }
            }

            Text("AltStore signs apps with its own Apple ID sign-in. AltLoad's AltServer puts them on this iPhone, manages their profiles and gives AltStore anisette data from your anisette server. JIT isn't supported.")
                .font(.system(size: 13))
                .foregroundStyle(Aurora.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .navigationTitle("AltServer")
        .toolbarTitleDisplayMode(.inlineLarge)
        .animation(.spring(duration: 0.4), value: host.activity)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                vpnActive = LocalDevVPN.isActive
                host.refresh()
            }
        }
        .onAppear { vpnActive = LocalDevVPN.isActive }
    }

    private var header: some View {
        GlassCard(padding: 22) {
            HStack(spacing: 16) {
                GlassBadge(systemImage: "server.rack", tint: host.isRunning ? Aurora.success : Aurora.violet, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.isRunning ? "AltServer is running" : "AltServer is off")
                        .font(.title3.bold())
                    Text(host.lastContact.map { "AltStore last connected \($0.formatted(.relative(presentation: .named)))" }
                         ?? "AltStore hasn't connected yet")
                        .font(.subheadline)
                        .foregroundStyle(Aurora.secondaryText)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func eventRow(_ event: AltServerHost.Event) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol(event.kind))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color(event.kind))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.weight(.semibold))
                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                        .textSelection(.enabled)
                }
                Text(event.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Aurora.secondaryText.opacity(0.8))
            }
            Spacer(minLength: 0)
        }
    }

    private func symbol(_ kind: AltServerHost.Event.Kind) -> String {
        switch kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    private func color(_ kind: AltServerHost.Event.Kind) -> Color {
        switch kind {
        case .info: Aurora.lilac
        case .success: Aurora.success
        case .failure: Aurora.danger
        }
    }
}
