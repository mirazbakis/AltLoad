import SwiftUI

/// AltLoad's palette: midnight navy, after Freight Manager's dark theme. Deep blue
/// gradient, a warm orange and a cyan glow, plain Liquid Glass, one blue accent.
/// No purple anywhere. The enum keeps its old name so every screen picks it up.
enum Aurora {
    // Base, from darkest to lightest.
    static let night = Color(red: 0.012, green: 0.027, blue: 0.071)      // #03071A
    static let card = Color(red: 0.035, green: 0.075, blue: 0.155)       // #091328
    static let navy = Color(red: 0.050, green: 0.150, blue: 0.280)       // #0D2647

    // Highlights.
    static let accent = Color(red: 0.180, green: 0.540, blue: 1.000)     // #2E8AFF
    static let sky = Color(red: 0.300, green: 0.820, blue: 0.950)        // #4DD1F2
    static let mist = Color(red: 0.690, green: 0.800, blue: 0.930)       // #B0CCED
    static let ember = Color.orange
    static let frost = Color.white

    static let success = Color(red: 0.300, green: 0.850, blue: 0.560)    // #4DD98F
    static let danger = Color(red: 1.000, green: 0.420, blue: 0.420)     // #FF6B6B

    /// Secondary text, white at 60%.
    static let secondaryText = Color.white.opacity(0.6)
    /// Hairline around cards.
    static let hairline = Color.white.opacity(0.08)

    /// Row fill for Lists and Forms.
    static let rowFill = card.opacity(0.75)

    static let accentGradient = LinearGradient(
        colors: [sky, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    static let markGradient = LinearGradient(
        colors: [Color(red: 0.16, green: 0.42, blue: 0.86), Color(red: 0.02, green: 0.05, blue: 0.13)],
        startPoint: .top,
        endPoint: .bottom)
}

extension View {
    /// Midnight look for every screen: forced dark, blue tint.
    func auroraTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Aurora.accent)
    }

    /// Navy cell background for Lists and Forms.
    func auroraRow() -> some View {
        listRowBackground(Aurora.rowFill)
    }

    /// Hides the default grouped background so the midnight gradient shows through.
    func auroraListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
    }
}
