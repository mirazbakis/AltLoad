import SwiftUI

/// Dark purple sky, lighter towards the top, with slowly drifting violet
/// light and a faint scatter of stars, so the Liquid Glass above it has
/// colour to refract.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            // Base: lit plum at the top, fading to deep purple.
            LinearGradient(
                colors: [Aurora.dusk, Aurora.deepBlue, Aurora.night],
                startPoint: .top,
                endPoint: .bottom)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: points(at: context.date),
                    colors: [
                        Aurora.indigo.opacity(0.9), Aurora.violet.opacity(0.55), Aurora.indigo.opacity(0.8),
                        Aurora.deepBlue.opacity(0.6), Aurora.orchid.opacity(0.35), Aurora.violet.opacity(0.4),
                        Aurora.night.opacity(0.0), Aurora.deepBlue.opacity(0.4), Aurora.night.opacity(0.0)
                    ]
                )
                .blendMode(.plusLighter)
                .opacity(0.75)
            }

            StarField()
                .blendMode(.screen)
                .opacity(0.35)

            // Soft light spilling down from the top edge.
            RadialGradient(
                colors: [Aurora.lilac.opacity(0.22), .clear],
                center: .init(x: 0.5, y: -0.1),
                startRadius: 20,
                endRadius: 480)

            // Gentle vignette to keep the edges calm.
            RadialGradient(
                colors: [.clear, Aurora.night.opacity(0.55)],
                center: .center,
                startRadius: 260,
                endRadius: 720)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func points(at date: Date) -> [SIMD2<Float>] {
        let t = Float(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
        let center = SIMD2<Float>(0.5 + 0.18 * sin(t * 0.19), 0.38 + 0.1 * cos(t * 0.15))
        let left = SIMD2<Float>(0, 0.45 + 0.1 * sin(t * 0.12))
        let right = SIMD2<Float>(1, 0.4 + 0.12 * cos(t * 0.17))
        let top = SIMD2<Float>(0.5 + 0.14 * cos(t * 0.1), 0)
        return [
            SIMD2(0, 0), top, SIMD2(1, 0),
            left, center, right,
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
        ]
    }
}

/// Deterministic, static star scatter drawn once with Canvas.
private struct StarField: View {
    private struct Star { let x, y, r, a: Double }

    private static let stars: [Star] = {
        var rng = SplitMix(seed: 0xA17_10AD)
        return (0..<60).map { _ in
            Star(x: rng.next(), y: rng.next() * 0.6, r: 0.4 + rng.next() * 0.9, a: 0.2 + rng.next() * 0.5)
        }
    }()

    var body: some View {
        Canvas { ctx, size in
            for s in Self.stars {
                let rect = CGRect(x: s.x * size.width, y: s.y * size.height, width: s.r * 2, height: s.r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Aurora.frost.opacity(s.a)))
            }
        }
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }
}

#Preview {
    AuroraBackground()
}
