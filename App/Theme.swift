import SwiftUI

/// AltLoad's aurora palette: night-sky navy, deep blue, violet and soft white.
enum Aurora {
    static let night = Color(red: 0.020, green: 0.027, blue: 0.086)     // #05071A
    static let deepBlue = Color(red: 0.055, green: 0.090, blue: 0.290)  // #0E174A
    static let indigo = Color(red: 0.180, green: 0.160, blue: 0.560)    // #2E298F
    static let violet = Color(red: 0.490, green: 0.340, blue: 0.990)    // #7D57FC
    static let lilac = Color(red: 0.760, green: 0.680, blue: 1.000)     // #C2ADFF
    static let frost = Color(red: 0.930, green: 0.940, blue: 1.000)     // #EDF0FF

    static let success = Color(red: 0.450, green: 0.880, blue: 0.780)   // aurora green
    static let danger = Color(red: 1.000, green: 0.450, blue: 0.560)

    static let accentGradient = LinearGradient(
        colors: [lilac, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing)
}

extension View {
    /// Dark aurora look for every screen.
    func auroraTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Aurora.violet)
    }
}
