import SwiftUI

/// About AltLoad: version, the people whose work it builds on, and the legal links.
/// Settings live behind the gear at the top right.
struct AboutView: View {
    @ObservedObject private var install = InstallController.shared
    @ObservedObject private var altServer = AltServerHost.shared
    @ObservedObject private var entitlements = EntitlementSettings.shared

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        let pre = Bundle.main.infoDictionary?["AltLoadPrerelease"] as? String ?? ""
        return pre.isEmpty ? "\(v) (\(b))" : "\(v) \(pre) (\(b))"
    }

    var body: some View {
        NavigationStack {
            AuroraScreen {
                hero

                HStack(spacing: 8) {
                    StatTile(title: "Apps", value: "\(install.apps.count)")
                    StatTile(title: "Entitlements", value: "\(entitlements.enabled.count)")
                    StatTile(title: "AltServer", value: altServer.isRunning ? "On" : "Off")
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Special Thanks")
                    VStack(spacing: 0) {
                        credit("jkcoxson", work: "idevice and LocalDevVPN: the link from this iPhone to itself",
                               symbol: "cable.connector", tint: Aurora.accentDeep, url: "https://github.com/jkcoxson")
                        divider
                        credit("nab138", work: "isideload: Apple ID sign-in and code signing",
                               symbol: "signature", tint: Aurora.forest, url: "https://github.com/nab138/isideload")
                        divider
                        credit("StephenDev0", work: "StikPair and StikDebug: pairing and JIT",
                               symbol: "antenna.radiowaves.left.and.right", tint: Color(red: 0.42, green: 0.30, blue: 0.70), url: "https://github.com/StephenDev0")
                        divider
                        credit("Riley Testut", work: "AltStore and the AltServer protocol",
                               symbol: "square.stack.3d.up.fill", tint: Color(red: 0.02, green: 0.48, blue: 0.48), url: "https://github.com/altstoreio/AltStore")
                        divider
                        credit("SideStore Team", work: "SideStore and the public anisette servers",
                               symbol: "arrow.triangle.2.circlepath", tint: Color(red: 0.55, green: 0.30, blue: 0.62), url: "https://github.com/SideStore")
                        divider
                        credit("LiveContainer", work: "Running apps without installing them",
                               symbol: "shippingbox.fill", tint: Color(red: 0.70, green: 0.42, blue: 0.16), url: "https://github.com/LiveContainer/LiveContainer")
                    }
                    .cardSurface()
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Legal")
                    VStack(spacing: 0) {
                        link("Terms of Service", symbol: "doc.text", url: "https://mirazbakis.github.io/terms.html")
                        divider
                        link("AltLoad License", symbol: "checkmark.seal", url: "https://github.com/mirazbakis/AltLoad/blob/main/LICENSE.md")
                        divider
                        link("Third-Party Notices", symbol: "list.bullet", url: "https://github.com/mirazbakis/AltLoad/blob/main/THIRD_PARTY_NOTICES.md")
                        divider
                        link("Security Policy", symbol: "lock.shield", url: "https://github.com/mirazbakis/AltLoad/blob/main/SECURITY.md")
                    }
                    .cardSurface()
                }

                VStack(spacing: 10) {
                    SectionLabel(title: "Project")
                    VStack(spacing: 0) {
                        link("Website", symbol: "globe", url: "https://mirazbakis.github.io/AltLoad.html")
                        divider
                        link("Source Code", symbol: "chevron.left.forwardslash.chevron.right", url: "https://github.com/mirazbakis/AltLoad")
                        divider
                        link("Report a Problem", symbol: "exclamationmark.bubble", url: "https://github.com/mirazbakis/AltLoad/issues")
                    }
                    .cardSurface()
                }

                Text("AltLoad isn't affiliated with AltStore, SideStore, LiveContainer, Riley Testut or Apple. Apple, iPhone and iOS are trademarks of Apple Inc.")
                    .font(.caption)
                    .foregroundStyle(Aurora.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("About")
            .toolbarTitleDisplayMode(.inlineLarge)
            .settingsButton()
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            AltLoadMark(size: 104)
            VStack(spacing: 4) {
                Text("AltLoad")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Aurora.frost)
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(Aurora.secondaryText)
            }
            Text("AltStore, SideStore and LiveContainer, signed and installed on this iPhone. No computer.")
                .font(.subheadline)
                .foregroundStyle(Aurora.mist)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Aurora.hairline)
            .frame(height: 1)
            .padding(.leading, 66)
    }

    private func credit(_ name: String, work: String, symbol: String, tint: Color, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Aurora.frost)
                    Text(work).font(.caption).foregroundStyle(Aurora.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Aurora.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .contentShape(.rect)
        }
    }

    private func link(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 14) {
                IconTile(symbol: symbol, tint: Aurora.mist, size: 36)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Aurora.frost)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Aurora.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
    }
}
