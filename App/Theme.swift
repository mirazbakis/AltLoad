import SwiftUI

/// AltLoad's palette, matched to Catalyst: pitch black, #6D40CC as the one accent,
/// deep plum (#140C20) cards with a faint violet hairline, near-white text.
/// The enum keeps its old name so every screen picks the new look up.
enum Aurora {
    // Base, from darkest to lightest.
    static let night = Color(red: 0.031, green: 0.020, blue: 0.055)      // #08050E, Catalyst settings background
    static let card = Color(red: 0.078, green: 0.047, blue: 0.125)       // #140C20, Catalyst cells and banner
    static let deepBlue = Color(red: 0.133, green: 0.078, blue: 0.220)   // #221438
    static let indigo = Color(red: 0.271, green: 0.161, blue: 0.502)     // #452980
    static let dusk = Color(red: 0.180, green: 0.106, blue: 0.318)       // #2E1B51

    // Highlights.
    static let violet = Color(red: 0.427, green: 0.251, blue: 0.800)     // #6D40CC, Catalyst primary
    static let orchid = Color(red: 0.608, green: 0.451, blue: 0.918)     // #9B73EA
    static let lilac = Color(red: 0.827, green: 0.776, blue: 0.965)      // #D3C6F6
    static let frost = Color.white

    static let success = Color(red: 0.431, green: 0.906, blue: 0.718)    // #6EE7B7
    static let danger = Color(red: 0.984, green: 0.443, blue: 0.522)     // #FB7185

    /// Secondary text, as in Catalyst's settings (white at 60%).
    static let secondaryText = Color.white.opacity(0.6)
    /// Hairline around cards (Catalyst: primary at 25%).
    static let hairline = violet.opacity(0.25)

    /// Row fill for Lists and Forms: Catalyst's #140C20 cells.
    static let rowFill = card

    static let accentGradient = LinearGradient(
        colors: [orchid, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    static let markGradient = LinearGradient(
        colors: [Color(red: 0.557, green: 0.373, blue: 0.941), Color(red: 0.118, green: 0.063, blue: 0.231)],
        startPoint: .top,
        endPoint: .bottom)
}

extension View {
    /// Catalyst look for every screen: forced dark, violet tint.
    func auroraTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Aurora.violet)
    }

    /// Catalyst cell background for Lists and Forms.
    func auroraRow() -> some View {
        listRowBackground(Aurora.rowFill)
    }

    /// Hides the default grouped background so the black + glow shows through.
    func auroraListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
    }
}
