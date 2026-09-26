import SwiftUI

/// Pitch-black background with one small, dark purple light that drifts slowly
/// near the top, so the Liquid Glass above it still has a little colour to catch.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            Color.black

            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height) * 0.85
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.30, green: 0.14, blue: 0.55).opacity(0.55),
                                    Color(red: 0.18, green: 0.07, blue: 0.36).opacity(0.25),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: size / 2))
                        .frame(width: size, height: size)
                        .blur(radius: 40)
                        .position(
                            x: geo.size.width * (0.5 + 0.08 * sin(t * 0.12)),
                            y: geo.size.height * (0.16 + 0.03 * cos(t * 0.1)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

#Preview {
    AuroraBackground()
}
