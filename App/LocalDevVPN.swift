import Darwin
import Foundation
import UIKit

/// LocalDevVPN (App Store, by jkcoxson / Stossy11) is a loopback VPN. It routes
/// 10.7.0.1 into a tunnel whose provider swaps each packet's source and
/// destination addresses and writes it straight back. A connection AltLoad opens
/// to 10.7.0.1 therefore arrives at this iPhone's own services as if it came from
/// another machine, which is what remotepairingd needs. No computer is involved.
enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6755608044")!
    static let defaultTargetIP = "10.7.0.1"
    /// remotepairingd's RemotePairing port (the same one StikDebug uses).
    static let remotePairingPort = 49152

    /// Opens LocalDevVPN, turns the VPN on and comes back to AltLoad via `altload://`.
    static let enableURL = URL(string: "localdevvpn://enable?scheme=altload")!

    static var targetIP: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "vpn.targetIP")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (stored?.isEmpty == false) ? stored! : defaultTargetIP
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == defaultTargetIP {
                UserDefaults.standard.removeObject(forKey: "vpn.targetIP")
            } else {
                UserDefaults.standard.set(trimmed, forKey: "vpn.targetIP")
            }
        }
    }

    @MainActor
    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "localdevvpn://")!)
    }

    /// True when a VPN interface (utun*) holds an address in the same /16 as the
    /// target (LocalDevVPN's defaults: interface 10.7.1.1, peer 10.7.0.1).
    static var isActive: Bool {
        let prefix = targetIP.split(separator: ".").prefix(2).joined(separator: ".") + "."
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard name.hasPrefix("utun"),
                  let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == sa_family_t(AF_INET),
                  (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0,
               String(cString: host).hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    /// Turns the VPN on if LocalDevVPN is installed; otherwise opens its App Store page.
    @MainActor
    static func turnOn() {
        UIApplication.shared.open(isInstalled ? enableURL : appStoreURL)
    }
}
