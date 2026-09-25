import SwiftUI

/// Full-width Liquid Glass action. Prominent actions get violet-tinted glass.
struct GlassActionButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var prominent = false
    var tint: Color = Aurora.violet
    let action: () -> Void

    var body: some View {
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(tint)
                .controlSize(.extraLarge)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
        }
    }

    private var label: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
            }
            Text(title)
                .font(.headline)
        }
        .foregroundStyle(Aurora.frost)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Rounded glass card used for instructions, status and details.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint((tint ?? Aurora.indigo).opacity(0.22)), in: .rect(cornerRadius: 26))
    }
}

/// Numbered step inside an instruction card.
struct GuideStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(Aurora.frost)
                .frame(width: 24, height: 24)
                .glassEffect(.regular.tint(Aurora.violet.opacity(0.6)), in: .circle)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Checklist row: done / pending / failed.
struct StatusRow: View {
    enum Status { case done, pending, attention }
    let title: LocalizedStringKey
    let detail: String
    let state: Status

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.tint(color.opacity(0.25)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var symbol: String {
        switch state {
        case .done: "checkmark"
        case .pending: "circle.dotted"
        case .attention: "exclamationmark"
        }
    }

    private var color: Color {
        switch state {
        case .done: Aurora.success
        case .pending: Aurora.lilac
        case .attention: Aurora.danger
        }
    }
}

/// Each digit of a pairing code in its own glass tile; the halves merge.
struct GlassCodeView: View {
    let code: String
    @Namespace private var ns

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(code.enumerated()), id: \.offset) { index, digit in
                    Text(String(digit))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Aurora.frost)
                        .frame(width: 44, height: 60)
                        .glassEffect(.regular.tint(Aurora.violet.opacity(0.25)).interactive(), in: .rect(cornerRadius: 14))
                        .glassEffectUnion(id: index < 3 ? "left" : "right", namespace: ns)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pairing code \(code.map(String.init).joined(separator: " "))")
    }
}

/// Symbol in a glass disc — the app mark and status icons.
struct GlassBadge: View {
    let systemImage: String
    var tint: Color = Aurora.violet
    var size: CGFloat = 96

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Aurora.frost)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.55)).interactive(), in: .circle)
    }
}

/// Small glass capsule for status text.
struct GlassChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Aurora.violet

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Aurora.frost)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular.tint(tint.opacity(0.3)), in: .capsule)
    }
}

/// Screen scaffold: aurora background + scrolling content column.
struct AuroraScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 24) {
                    content
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
