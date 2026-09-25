import SwiftUI

/// AltLoad's palette: a dark but softly lit purple, violet highlights and near-white text.
enum Aurora {
    // Base, from darkest to lightest.
    static let night = Color(red: 0.086, green: 0.051, blue: 0.169)      // #160D2B, bottom of the background
    static let deepBlue = Color(red: 0.165, green: 0.102, blue: 0.310)   // #2A1A4F, plum
    static let indigo = Color(red: 0.290, green: 0.180, blue: 0.549)     // #4A2E8C, amethyst
    static let dusk = Color(red: 0.200, green: 0.125, blue: 0.380)       // #332061, top of the background

    // Highlights.
    static let violet = Color(red: 0.545, green: 0.361, blue: 0.965)     // #8B5CF6
    static let orchid = Color(red: 0.753, green: 0.518, blue: 0.988)     // #C084FC
    static let lilac = Color(red: 0.867, green: 0.820, blue: 1.000)      // #DDD1FF
    static let frost = Color(red: 0.957, green: 0.941, blue: 1.000)      // #F4F0FF

    static let success = Color(red: 0.431, green: 0.906, blue: 0.718)    // #6EE7B7
    static let danger = Color(red: 0.984, green: 0.443, blue: 0.522)     // #FB7185

    /// Soft fill for list and form rows on top of the purple background.
    static let rowFill = Color.white.opacity(0.07)

    static let accentGradient = LinearGradient(
        colors: [orchid, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)

    static let markGradient = LinearGradient(
        colors: [Color(red: 0.624, green: 0.420, blue: 1.000), Color(red: 0.165, green: 0.086, blue: 0.314)],
        startPoint: .top,
        endPoint: .bottom)
}

extension View {
    /// Dark purple look for every screen.
    func auroraTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Aurora.violet)
    }

    /// Translucent row background for Lists and Forms on the aurora background.
    func auroraRow() -> some View {
        listRowBackground(Aurora.rowFill)
    }

    /// Hides the default grouped background so the aurora shows through.
    func auroraListBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
    }
}
