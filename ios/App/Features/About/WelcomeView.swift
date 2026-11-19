import SwiftUI

/// Shown once, the first time AltLoad opens. Continue goes on to the app.
struct WelcomeView: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 18) {
                    AltLoadMark(size: 140)
                        .scaleEffect(appeared ? 1 : 0.85)
                    VStack(spacing: 6) {
                        Text("AltLoad")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(Aurora.frost)
                        Text("Created by Miraz Bakis")
                            .font(.headline)
                            .foregroundStyle(Aurora.mist)
                    }
                }
                .opacity(appeared ? 1 : 0)
                Spacer()
                VStack(spacing: 12) {
                    GlassActionButton(title: "Continue", prominent: true, action: onContinue)
                    Text("Official downloads: altload.org")
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                }
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) { appeared = true }
        }
    }
}

#Preview {
    WelcomeView {}
        .auroraTheme()
}
