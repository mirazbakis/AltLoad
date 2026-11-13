//! Picks this iPhone's Wi-Fi IPv4 address out of `ifconfig` output, and decides
//! which addresses are worth announcing.

use std::net::Ipv4Addr;

/// True for an address another device on the Wi-Fi could reach us at.
/// Rejects 0.0.0.0, 127.x (loopback) and 169.254.x (link-local).
pub fn is_lan_candidate(ip: Ipv4Addr) -> bool {
    !(ip.is_unspecified() || ip.is_loopback() || ip.is_link_local())
}

/// Like [`is_lan_candidate`], but also rejects 100.64.0.0/10, the shared range
/// used by carrier NAT and by VPNs such as Tailscale. Used for an address the
/// system picked by routing, which may be a cellular or VPN interface.
pub fn is_likely_wifi(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    let shared = o[0] == 100 && (o[1] & 0xc0) == 64;
    is_lan_candidate(ip) && !shared
}

/// Returns the first `inet A.B.C.D` (or `inet addr:A.B.C.D`) address in the text
/// that is not loopback or link-local. `inet6` lines are ignored.
pub fn parse_inet(text: &str) -> Option<Ipv4Addr> {
    for line in text.lines() {
        let mut words = line.split_whitespace();
        while let Some(w) = words.next() {
            if w != "inet" {
                continue;
            }
            let Some(next) = words.next() else { break };
            let addr = next.strip_prefix("addr:").unwrap_or(next);
            // Some tools print A.B.C.D/NN.
            let addr = addr.split('/').next().unwrap_or(addr);
            if let Ok(ip) = addr.parse::<Ipv4Addr>() {
                if is_lan_candidate(ip) {
                    return Some(ip);
                }
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    const EN0: &str = "en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
\toptions=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>
\tether 1a:2b:3c:4d:5e:6f
\tinet6 fe80::1c2b:3cff:fe4d:5e6f%en0 prefixlen 64 secured scopeid 0xb
\tinet 192.168.1.42 netmask 0xffffff00 broadcast 192.168.1.255
\tnd6 options=201<PERFORMNUD,DAD>
\tmedia: autoselect
\tstatus: active
";

    #[test]
    fn parses_darwin_en0() {
        assert_eq!(parse_inet(EN0), Some(Ipv4Addr::new(192, 168, 1, 42)));
    }

    #[test]
    fn skips_loopback_and_link_local() {
        let text = "lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
\tinet 127.0.0.1 netmask 0xff000000
en0: flags=8863<UP>
\tinet 169.254.10.3 netmask 0xffff0000
\tinet 10.0.0.7 netmask 0xffffff00 broadcast 10.0.0.255
";
        assert_eq!(parse_inet(text), Some(Ipv4Addr::new(10, 0, 0, 7)));
    }

    #[test]
    fn parses_linux_style_and_cidr() {
        assert_eq!(
            parse_inet("  inet addr:172.16.5.9  Bcast:172.16.5.255"),
            Some(Ipv4Addr::new(172, 16, 5, 9))
        );
        assert_eq!(
            parse_inet("    inet 192.168.0.3/24 brd 192.168.0.255 scope global"),
            Some(Ipv4Addr::new(192, 168, 0, 3))
        );
    }

    #[test]
    fn nothing_usable() {
        assert_eq!(parse_inet(""), None);
        assert_eq!(parse_inet("\tinet6 fe80::1%en0 prefixlen 64"), None);
        assert_eq!(parse_inet("\tinet 127.0.0.1 netmask 0xff000000"), None);
        assert_eq!(parse_inet("en0: flags=8822<BROADCAST> mtu 1500\n\tstatus: inactive"), None);
    }

    #[test]
    fn wifi_filter() {
        assert!(is_likely_wifi(Ipv4Addr::new(192, 168, 1, 2)));
        assert!(!is_likely_wifi(Ipv4Addr::new(100, 101, 2, 3)));
        assert!(is_likely_wifi(Ipv4Addr::new(100, 128, 0, 1)));
        assert!(!is_likely_wifi(Ipv4Addr::new(0, 0, 0, 0)));
        assert!(!is_likely_wifi(Ipv4Addr::new(169, 254, 1, 1)));
    }
}
