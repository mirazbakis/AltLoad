import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AltLoadWidgets: WidgetBundle {
    var body: some Widget {
        PairingLiveActivity()
    }
}

/// The pairing code in the Dynamic Island and on the Lock Screen, so it can be
/// read while Settings is open on top of AltLoad.
struct PairingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PairingActivityAttributes.self) { context in
            LockScreenView(state: context.state, hostName: context.attributes.hostName)
                .activityBackgroundTint(Palette.night.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusGlyph(status: context.state.status, size: 40)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(context.state.status.tint)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    CodeText(state: context.state, size: 34)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.status.instruction(hostName: context.attributes.hostName))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            } compactLeading: {
                StatusGlyph(status: context.state.status, size: 22)
            } compactTrailing: {
                if let code = context.state.code, context.state.status == .code {
                    Text(code)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.sky)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: context.state.status.symbol)
                        .foregroundStyle(context.state.status.tint)
                }
            } minimal: {
                StatusGlyph(status: context.state.status, size: 22)
            }
            .keylineTint(Palette.accent)
        }
    }
}

// MARK: - Pieces

private struct LockScreenView: View {
    let state: PairingActivityAttributes.ContentState
    let hostName: String

    var body: some View {
        HStack(spacing: 14) {
            StatusGlyph(status: state.status, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                CodeText(state: state, size: 30)
                Text(state.status.instruction(hostName: hostName))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// The code in large rounded digits, or the status line when there's no code.
private struct CodeText: View {
    let state: PairingActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if let code = state.groupedCode, state.status == .code {
                Text(code)
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Pairing code \(code)")
            } else {
                Text(state.status.headline)
                    .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The status symbol in a tinted circle.
private struct StatusGlyph: View {
    let status: PairingActivityAttributes.ContentState.Status
    let size: CGFloat

    var body: some View {
        Image(systemName: status.symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(status.tint.gradient, in: .circle)
    }
}

private extension PairingActivityAttributes.ContentState.Status {
    var symbol: String {
        switch self {
        case .waiting: "antenna.radiowaves.left.and.right"
        case .code: "lock.open.fill"
        case .paired: "checkmark"
        case .failed: "xmark"
        }
    }

    var tint: Color {
        switch self {
        case .waiting, .code: Palette.accent
        case .paired: Palette.success
        case .failed: Palette.danger
        }
    }

    var title: String {
        switch self {
        case .waiting: "Waiting"
        case .code: "Pairing code"
        case .paired: "Paired"
        case .failed: "Failed"
        }
    }

    var headline: String {
        switch self {
        case .waiting: "Waiting…"
        case .code: "Pairing code"
        case .paired: "Paired"
        case .failed: "Pairing failed"
        }
    }

    func instruction(hostName: String) -> String {
        switch self {
        case .waiting: "Settings › Privacy & Security › Developer Mode › Pair with \(hostName)"
        case .code: "Enter this code in Settings to pair with \(hostName)."
        case .paired: "Return to \(hostName) to finish."
        case .failed: "Open \(hostName) to try again."
        }
    }
}

/// AltLoad's colors, repeated here because the extension doesn't link the app's theme.
private enum Palette {
    static let night = Color(red: 0.012, green: 0.020, blue: 0.043)
    static let accent = Color(red: 0.235, green: 0.478, blue: 0.890)
    static let sky = Color(red: 0.490, green: 0.690, blue: 0.980)
    static let success = Color(red: 0.250, green: 0.760, blue: 0.500)
    static let danger = Color(red: 0.960, green: 0.380, blue: 0.400)
}
