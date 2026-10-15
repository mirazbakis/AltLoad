import SwiftUI

/// AltLoad's palette: Freight Manager's navy tone, taken darker. A midnight base,
/// one dark navy spotlight, solid navy surfaces and a deep blue accent. The dark
/// green and white come from the app icon. The enum keeps its old name so every
/// screen picks it up.
enum Aurora {
    // Base, from darkest to lightest.
    static let night = Color(red: 0.012, green: 0.020, blue: 0.043)      // #03050B
    static let spotlight = Color(red: 0.055, green: 0.125, blue: 0.290)  // #0E204A
    static let card = Color(red: 0.039, green: 0.063, blue: 0.118)       // #0A101E
    static let raised = Color(red: 0.063, green: 0.098, blue: 0.173)     // #10192C
    static let navy = Color(red: 0.075, green: 0.161, blue: 0.333)       // #132955

    // Highlights.
    static let accent = Color(red: 0.235, green: 0.478, blue: 0.890)     // #3C7AE3
    static let accentDeep = Color(red: 0.122, green: 0.282, blue: 0.620) // #1F489E
    static let sky = Color(red: 0.490, green: 0.690, blue: 0.980)        // #7DB0FA
    static let mist = Color(red: 0.640, green: 0.720, blue: 0.840)       // #A3B8D6
    static let forest = Color(red: 0.090, green: 0.420, blue: 0.290)     // #176B4A, the icon's green
    static let ember = Color.orange
    static let frost = Color.white

    static let success = Color(red: 0.250, green: 0.760, blue: 0.500)    // #40C280
    static let danger = Color(red: 0.960, green: 0.380, blue: 0.400)     // #F56166

    /// Secondary text, white at 58%.
    static let secondaryText = Color.white.opacity(0.58)
    /// Hairline around cards.
    static let hairline = Color.white.opacity(0.07)

    /// Row fill for Lists and Forms.
    static let rowFill = card

    static let accentGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .top,
        endPoint: .bottom)

    /// The icon's background: midnight into dark green.
    static let markGradient = LinearGradient(
        colors: [Color(red: 0.035, green: 0.075, blue: 0.130), Color(red: 0.020, green: 0.200, blue: 0.140)],
        startPoint: .top,
        endPoint: .bottomTrailing)
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

    /// Hides the default grouped background so the midnight background shows through.
    func auroraListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
    }
}
