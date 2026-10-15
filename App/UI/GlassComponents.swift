import SwiftUI

// AltLoad's own components: solid midnight surfaces with a hairline edge, big
// filled buttons, no glass on content (the system tab bar keeps its own).
// The old "Glass" names stay so every screen picks the new look up.

// MARK: - Buttons & cards

/// Full-width action, 56 pt tall. Prominent actions are filled with the accent.
struct GlassActionButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var prominent = false
    var tint: Color = Aurora.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(AltLoadButtonStyle(prominent: prominent, tint: tint))
    }
}

/// Filled (prominent) or quiet button surface with a press state.
struct AltLoadButtonStyle: ButtonStyle {
    var prominent = true
    var tint: Color = Aurora.accent
    var radius: CGFloat = 18
    var minHeight: CGFloat = 50
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: minHeight)
            .foregroundStyle(prominent ? Aurora.frost : (tint == Aurora.accent ? Aurora.frost : tint))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(prominent
                          ? AnyShapeStyle(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.35)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Aurora.raised))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(prominent ? Color.white.opacity(0.14) : Aurora.hairline, lineWidth: 1)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Card: a solid midnight surface with a hairline, or a faint status tint.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(tint: tint)
    }
}

extension View {
    /// The card background used everywhere: solid navy, hairline, 22 pt corners.
    func cardSurface(tint: Color? = nil, radius: CGFloat = 22) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Aurora.card)
                .overlay {
                    if let tint {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(tint.opacity(0.12))
                    }
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(tint.map { $0.opacity(0.32) } ?? Aurora.hairline, lineWidth: 1)
        }
    }
}

/// Section header: 13pt semibold, uppercase, white at 58%.
struct SectionLabel: View {
    let title: LocalizedStringKey
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Aurora.secondaryText)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Aurora.secondaryText)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Icon in a rounded square, the way rows in About and Settings lead.
struct IconTile: View {
    let symbol: String
    var tint: Color = Aurora.accent
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(Aurora.frost)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// A titled card: icon tile + headline, then its rows.
struct CardSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    IconTile(symbol: symbol, tint: tint ?? Aurora.accentDeep, size: 30)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Aurora.frost)
                }
                content
            }
        }
    }
}

/// Title on the left, value on the right.
struct InfoRow: View {
    let title: LocalizedStringKey
    let value: String
    var symbol: String? = nil
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(Aurora.secondaryText).frame(width: 22)
            }
            Text(title).foregroundStyle(Aurora.secondaryText)
            Spacer(minLength: 12)
            Text(value.isEmpty ? "—" : value)
                .fontWeight(.medium)
                .fontDesign(monospaced ? .monospaced : .default)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

/// A row that opens another screen: icon tile, title, optional value, chevron. 64 pt tall.
struct LinkCard<Destination: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    var value: String? = nil
    var tint: Color = Aurora.accentDeep
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, tint: tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Aurora.frost)
                Spacer()
                if let value {
                    Text(value).font(.subheadline).foregroundStyle(Aurora.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Aurora.secondaryText.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .cardSurface()
    }
}

/// Small number-over-caption tile for a card's summary row.
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit().foregroundStyle(Aurora.frost)
            Text(title).font(.caption).foregroundStyle(Aurora.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Aurora.raised, in: .rect(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// Plain field for use inside cards.
    func inputField() -> some View {
        self
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(Aurora.raised, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Aurora.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Settings button

/// The gear at the top right of each tab. A standard toolbar button, so it gets
/// the same Liquid Glass circle and tint as the other toolbar buttons.
struct SettingsToolbarButton: ToolbarContent {
    @Binding var isPresented: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isPresented = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

// MARK: - App cells

/// App icon from a source, or a gradient tile with a symbol while it loads.
struct AppIconView: View {
    var url: URL?
    var symbol: String = "app.fill"
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Aurora.accentGradient)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(Aurora.frost)
                }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}

/// Capsule button for app rows: an optional caption over a bold title
/// ("EXPIRES IN" / "5 DAYS"), or one word ("REFRESH"). At least 44 × 92 pt.
struct PillButton: View {
    var caption: String? = nil
    let title: String
    var tint: Color = Aurora.accent
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                if let caption {
                    Text(caption.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.8)
                }
                Text(title.uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(prominent ? Aurora.frost : tint)
            .padding(.horizontal, 16)
            .frame(minWidth: 92, minHeight: 44)
            .background(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.16)), in: .capsule)
            .overlay { Capsule().strokeBorder(Color.white.opacity(prominent ? 0.14 : 0.06), lineWidth: 1) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// An app row: icon, name, detail line and a button on the right.
struct AppBannerRow<Trailing: View>: View {
    let name: String
    let detail: String
    var detailColor: Color = Aurora.secondaryText
    var iconURL: URL? = nil
    var symbol: String = "app.fill"
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            AppIconView(url: iconURL, symbol: symbol, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Aurora.frost)
                    .lineLimit(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
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
                .frame(width: 26, height: 26)
                .background(Aurora.accentDeep, in: .circle)
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
                .frame(width: 34, height: 34)
                .background(color.opacity(0.16), in: .circle)
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
        case .pending: Aurora.mist
        case .attention: Aurora.danger
        }
    }
}

// MARK: - Indicators

/// Each digit of a pairing code in its own tile, in two groups of three.
struct GlassCodeView: View {
    let code: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(code.enumerated()), id: \.offset) { index, digit in
                Text(String(digit))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Aurora.frost)
                    .frame(width: 44, height: 60)
                    .background(Aurora.raised, in: .rect(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Aurora.accent.opacity(0.35), lineWidth: 1)
                    }
                    .padding(.leading, index == 3 ? 10 : 0)
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
                .stroke(Aurora.frost.opacity(0.10), lineWidth: lineWidth)

            TimelineView(.animation(paused: value != nil)) { context in
                let spin = value == nil
                    ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1 * 360
                    : 0
                Circle()
                    .trim(from: 0, to: value.map { max(0.02, min($0, 1)) } ?? 0.28)
                    .stroke(Aurora.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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

/// Linear progress on a dark track, accent fill.
struct GlassProgressBar: View {
    var value: Double
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Aurora.raised)
                Capsule()
                    .fill(Aurora.accent)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(.spring(duration: 0.5), value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
    }
}

// MARK: - Marks

/// Symbol in a tinted disc, used for status icons.
struct GlassBadge: View {
    let systemImage: String
    var tint: Color = Aurora.accent
    var size: CGFloat = 96

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Aurora.frost)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .circle)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            .shadow(color: tint.opacity(0.35), radius: size * 0.25)
    }
}

/// Small capsule for status text.
struct GlassChip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Aurora.accent

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Aurora.frost)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.18), in: .capsule)
        .overlay { Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1) }
    }
}

/// AltLoad's logo drawn in SwiftUI: a white arrow into a tray, inside an orbit, with
/// sparkles, on midnight fading into dark green.
/// Matches the app icon (App/AltLoad.icon) and docs/assets/logo.svg.
struct AltLoadMark: View {
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Aurora.markGradient)
            RadialGradient(colors: [Color(red: 0.25, green: 0.75, blue: 0.52).opacity(0.32), .clear],
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

            LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: Aurora.forest.opacity(0.45), radius: size * 0.2, y: size * 0.06)
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

/// Screen scaffold: midnight background edge to edge, scrolling content column.
struct AuroraScreen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 22) {
                    content
                }
                .frame(maxWidth: 680)
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

// MARK: - Settings sheet

private struct SettingsButtonModifier: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .toolbar { SettingsToolbarButton(isPresented: $isPresented) }
            .sheet(isPresented: $isPresented) {
                SettingsView()
                    .auroraTheme()
                    .presentationBackground(Aurora.night)
            }
    }
}

extension View {
    /// Adds the gear circle at the top right that opens Settings.
    func settingsButton() -> some View {
        modifier(SettingsButtonModifier())
    }
}
