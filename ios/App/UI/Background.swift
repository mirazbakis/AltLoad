import SwiftUI

/// Pure black background with a small, dim navy glow falling from the top.
/// Static: nothing drifts behind the content.
struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Aurora.night
                EllipticalGradient(
                    colors: [Aurora.glow.opacity(0.7), Aurora.glow.opacity(0.25), .clear],
                    center: .center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5)
                    .frame(width: geo.size.width * 1.2, height: min(geo.size.height * 0.5, 420))
                    .position(x: geo.size.width / 2, y: 0)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    AppBackground()
}
