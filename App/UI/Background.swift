import SwiftUI

/// Full midnight background with a single dark navy spotlight falling from the top.
/// Static: nothing drifts or glows behind the content.
struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Aurora.night
                EllipticalGradient(
                    colors: [Aurora.spotlight.opacity(0.95), Aurora.spotlight.opacity(0.35), .clear],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.5)
                    .frame(width: geo.size.width * 1.5, height: min(geo.size.height * 0.9, 760))
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
