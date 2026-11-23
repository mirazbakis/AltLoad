//! Picks this iPhone's Wi-Fi IPv4 address out of `ifconfig` output.

use std::io::Read;
use std::net::Ipv4Addr;

/// True for an address another device on the Wi-Fi could reach us at.
/// Rejects 0.0.0.0, 127.x (loopback) and 169.254.x (link-local).
pub fn is_lan_candidate(ip: Ipv4Addr) -> bool {
    !(ip.is_unspecified() || ip.is_loopback() || ip.is_link_local())
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

/// Reads `ifconfig` text until it contains an address, then stops. Only whole
/// lines are parsed, so an address split across two reads isn't cut short.
/// rootshell doesn't always end a `<` redirect, so waiting for EOF can hang.
/// Returns the address, if any, and how many bytes were read.
pub fn read_until_address(r: &mut impl Read, limit: usize) -> (Option<Ipv4Addr>, usize) {
    let mut text = Vec::new();
    let mut buf = [0u8; 4096];
    while text.len() < limit {
        let n = match r.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => n,
        };
        text.extend_from_slice(&buf[..n]);
        if let Some(end) = text.iter().rposition(|&b| b == b'\n') {
            if let Some(ip) = parse_inet(&String::from_utf8_lossy(&text[..end])) {
                return (Some(ip), text.len());
            }
        }
    }
    (parse_inet(&String::from_utf8_lossy(&text)), text.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Gives its chunks, then fails the test if read again (like a stdin with no EOF).
    struct NoEof(Vec<&'static [u8]>);
    impl Read for NoEof {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            assert!(!self.0.is_empty(), "read past the address: this would hang");
            let chunk = self.0.remove(0);
            buf[..chunk.len()].copy_from_slice(chunk);
            Ok(chunk.len())
        }
    }

    #[test]
    fn stops_once_an_address_arrives() {
        let mut r = NoEof(vec![b"en0: flags=8863<UP>\n\tinet 192.168.1.", b"42 netmask 0xffffff00\n"]);
        assert_eq!(read_until_address(&mut r, 1 << 16).0, Some(Ipv4Addr::new(192, 168, 1, 42)));
    }

    #[test]
    fn reads_to_eof_without_a_newline() {
        let text: &[u8] = b"\tinet 10.0.0.7 netmask 0xffffff00";
        assert_eq!(read_until_address(&mut &text[..], 1 << 16).0, Some(Ipv4Addr::new(10, 0, 0, 7)));
        let empty: &[u8] = b"";
        assert_eq!(read_until_address(&mut &empty[..], 1 << 16), (None, 0));
    }

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
}
