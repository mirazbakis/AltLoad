import SwiftUI

// MARK: - Buttons & cards

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
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint((tint ?? Aurora.violet).opacity(tint == nil ? 0.12 : 0.22)), in: .rect(cornerRadius: 28))
    }
}

/// Small uppercase label above a group of cards.
struct SectionLabel: View {
    let title: LocalizedStringKey
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Aurora.lilac.opacity(0.75))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Aurora.lilac.opacity(0.75))
            }
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - Rows

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

/// Checklist row: done / pending / needs attention.
struct StatusRow: View {
    enum Status { case done, pending, attention }
    let title: LocalizedStringKey
    let detail: String
    let state: Status

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .glassEffect(.regular.tint(color.opacity(0.22)), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

// MARK: - Indicators

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

/// Circular progress. `value == nil` spins indefinitely.
struct ProgressRing: View {
    var value: Double?
    var lineWidth: CGFloat = 8
    var size: CGFloat = 64
    var showsPercent = true

    var body: some View {
        ZStack {
            Circle()
                .stroke(Aurora.frost.opacity(0.12), lineWidth: lineWidth)

            TimelineView(.animation(paused: value != nil)) { context in
                let spin = value == nil
                    ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
                    : 0
                Circle()
                    .trim(from: 0, to: value.map { max(0.02, min($0, 1)) } ?? 0.28)
                    .stroke(
                        AngularGradient(colors: [Aurora.orchid, Aurora.violet, Aurora.orchid], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spin - 90))
                    .animation(.spring(duration: 0.4), value: value)
            }

            if showsPercent, let value {
                Text(value.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Aurora.frost)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(Int($0 * 100)) percent" } ?? "In progress")
    }
}

// MARK: - Marks

/// Symbol in a glass disc, used for status icons.
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
            .background {
                Circle()
                    .fill(tint.opacity(0.45))
                    .blur(radius: size * 0.35)
                    .scaleEffect(1.1)
            }
            .glassEffect(.regular.tint(tint.opacity(0.5)).interactive(), in: .circle)
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

/// AltLoad's logo drawn in SwiftUI: arrow into a tray, inside an orbit, with sparkles.
/// Matches the app icon (App/AltLoad.icon) and docs/assets/logo.svg.
struct AltLoadMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Aurora.markGradient)
            RadialGradient(colors: [Aurora.lilac.opacity(0.5), .clear],
                           center: .init(x: 0.5, y: 0.47), startRadius: 0, endRadius: size * 0.42)

            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: size * 0.027)
                .frame(width: size * 0.66, height: size * 0.66)
                .offset(y: -size * 0.012)

            MarkShape(kind: .arrow)
                .fill(Color.white)
                .frame(width: size * 0.293, height: size * 0.332)
                .offset(y: -size * 0.117)

            MarkShape(kind: .tray)
                .fill(Color.white)
                .frame(width: size * 0.449, height: size * 0.176)
                .offset(y: size * 0.158)

            MarkShape(kind: .sparkle)
                .fill(Color.white)
                .frame(width: size * 0.137, height: size * 0.137)
                .offset(x: size * 0.252, y: -size * 0.26)

            MarkShape(kind: .sparkle)
                .fill(Color.white.opacity(0.8))
                .frame(width: size * 0.062, height: size * 0.062)
                .offset(x: -size * 0.239, y: size * 0.205)

            LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: Aurora.violet.opacity(0.55), radius: size * 0.22, y: size * 0.06)
        .accessibilityLabel("AltLoad")
    }
}

/// The logo's glyphs, traced from the icon SVGs and scaled to any frame.
private struct MarkShape: Shape {
    enum Kind { case arrow, tray, sparkle }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .arrow:
            // 300 × 340 design space.
            let sx = rect.width / 300, sy = rect.height / 340
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
            let w: CGFloat = 60
            p.addRoundedRect(in: CGRect(origin: pt(150 - w / 2, 0), size: CGSize(width: w * sx, height: 250 * sy)),
                             cornerSize: CGSize(width: 30 * sx, height: 30 * sy))
            var head = Path()
            head.move(to: pt(40, 180))
            head.addLine(to: pt(150, 290))
            head.addLine(to: pt(260, 180))
            p.addPath(head.strokedPath(StrokeStyle(lineWidth: w * sx, lineCap: .round, lineJoin: .round)))
        case .tray:
            // 460 × 180 design space.
            let sx = rect.width / 460, sy = rect.height / 180
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
            var u = Path()
            u.move(to: pt(30, 30))
            u.addLine(to: pt(30, 100))
            u.addQuadCurve(to: pt(80, 150), control: pt(30, 150))
            u.addLine(to: pt(380, 150))
            u.addQuadCurve(to: pt(430, 100), control: pt(430, 150))
            u.addLine(to: pt(430, 30))
            p.addPath(u.strokedPath(StrokeStyle(lineWidth: 60 * sx, lineCap: .round, lineJoin: .round)))
        case .sparkle:
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let r = min(rect.width, rect.height) / 2
            let k = r * 0.14
            p.move(to: CGPoint(x: c.x, y: c.y - r))
            p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
            p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
            p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
            p.closeSubpath()
        }
        return p
    }
}

// MARK: - Scaffold

/// Screen scaffold: aurora background + scrolling content column.
struct AuroraScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 22) {
                    content
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

#Preview("Mark") {
    ZStack {
        AuroraBackground()
        VStack(spacing: 30) {
            AltLoadMark(size: 160)
            ProgressRing(value: 0.42, size: 80)
            ProgressRing(value: nil, size: 48)
        }
    }
    .auroraTheme()
}
