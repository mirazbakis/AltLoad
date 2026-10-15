import SwiftUI

/// Midnight background, after Freight Manager's dark theme: a navy gradient with a
/// warm orange glow top-right and a cyan one bottom-left, both drifting slowly so
/// the Liquid Glass above has some colour to catch.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.07, blue: 0.16),
                    Color(red: 0.05, green: 0.15, blue: 0.28),
                    Aurora.night
                ],
                startPoint: .top,
                endPoint: .bottomTrailing)

            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    Circle()
                        .fill(Color.orange.opacity(0.20))
                        .frame(width: 320, height: 320)
                        .blur(radius: 90)
                        .position(
                            x: geo.size.width + 50 + 20 * sin(t * 0.12),
                            y: 70 + 14 * cos(t * 0.1))
                    Circle()
                        .fill(Color.cyan.opacity(0.20))
                        .frame(width: 360, height: 360)
                        .blur(radius: 100)
                        .position(
                            x: -50 + 20 * cos(t * 0.09),
                            y: geo.size.height - 90 + 14 * sin(t * 0.11))
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
