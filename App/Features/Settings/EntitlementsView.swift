import SwiftUI

/// Settings › Entitlements: switches for capabilities AltStore is signed with.
struct EntitlementsView: View {
    @ObservedObject private var settings = EntitlementSettings.shared

    var body: some View {
        AuroraScreen {
            Text("Switched-on entitlements are enabled on AltStore's App ID with your Apple ID, then added to its signature the next time you install or refresh it.")
                .font(.footnote)
                .foregroundStyle(Aurora.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            CardSection(title: "Free Apple ID", symbol: "person") {
                ForEach(Capability.all.filter { $0.tier == .free }) { row($0) }
                note("Personal teams can usually enable these.")
            }

            CardSection(title: "Paid Developer Account", symbol: "star", tint: Aurora.ember) {
                ForEach(Capability.all.filter { $0.tier == .paid }) { row($0) }
                note("These need an Apple Developer Program membership. On a free Apple ID, Apple refuses them and the install stops with the reason, so leave them off there.")
            }

            Button(role: .destructive) {
                settings.enabled = []
            } label: {
                Label("Turn All Off", systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(AltLoadButtonStyle(prominent: false, tint: Aurora.danger))
            .disabled(settings.enabled.isEmpty)

            note("Turning one off stops AltLoad asking for it. Apple keeps it on the App ID until you remove it at developer.apple.com, so the profile may still include it.")
                .multilineTextAlignment(.center)
        }
        .navigationTitle("Entitlements")
        .toolbarTitleDisplayMode(.inline)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Aurora.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ capability: Capability) -> some View {
        Toggle(isOn: settings.binding(capability)) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(capability.name)
                    Text(capability.detail)
                        .font(.caption)
                        .foregroundStyle(Aurora.secondaryText)
                }
            } icon: {
                Image(systemName: capability.symbol)
                    .foregroundStyle(capability.tier == .paid ? Aurora.ember : Aurora.sky)
            }
        }
    }
}

#Preview {
    NavigationStack { EntitlementsView() }
        .auroraTheme()
}
