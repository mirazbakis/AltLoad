//! Plain data helpers for rootshell's socket interface: constants, the
//! `sockaddr_in` byte layout (family in the first byte, no length byte) and
//! errno names. The host calls themselves live in `host.rs`.

use std::net::Ipv4Addr;

pub const AF_INET: i32 = 2;
pub const SOCK_STREAM: i32 = 1;
pub const SOCK_DGRAM: i32 = 2;
pub const SHUT_WR: i32 = 1;
pub const SOCKADDR_IN_LEN: usize = 16;
/// Room for the largest address the host may write back (`sockaddr_in6`).
pub const SOCKADDR_MAX: usize = 28;

/// 16-byte `sockaddr_in`: family, 0, port (big-endian), address, 8 zero bytes.
pub fn sockaddr_in(ip: Ipv4Addr, port: u16) -> [u8; SOCKADDR_IN_LEN] {
    let mut out = [0u8; SOCKADDR_IN_LEN];
    out[0] = AF_INET as u8;
    out[2..4].copy_from_slice(&port.to_be_bytes());
    out[4..8].copy_from_slice(&ip.octets());
    out
}

/// Reads an IPv4 address and port back out of a `sockaddr_in`.
pub fn parse_sockaddr_in(buf: &[u8]) -> Option<(Ipv4Addr, u16)> {
    if buf.len() < 8 || buf[0] != AF_INET as u8 {
        return None;
    }
    let port = u16::from_be_bytes([buf[2], buf[3]]);
    Some((Ipv4Addr::new(buf[4], buf[5], buf[6], buf[7]), port))
}

pub fn errno_name(e: i32) -> &'static str {
    match e {
        0 => "OK",
        1 => "EADDRINUSE",
        2 => "EACCES",
        8 => "EBADF",
        14 => "ECONNREFUSED",
        27 => "EINTR",
        28 => "EINVAL",
        29 => "EIO",
        44 => "ENOENT",
        50 => "ENETUNREACH",
        52 => "ENOSYS",
        73 => "ETIMEDOUT",
        _ => "error",
    }
}

pub fn errno_text(e: i32) -> String {
    format!("{} ({e})", errno_name(e))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sockaddr_round_trip() {
        let a = sockaddr_in(Ipv4Addr::new(127, 0, 0, 1), 47627);
        assert_eq!(a, [2, 0, 0xba, 0x0b, 127, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]);
        assert_eq!(parse_sockaddr_in(&a), Some((Ipv4Addr::new(127, 0, 0, 1), 47627)));
        assert_eq!(parse_sockaddr_in(&[30, 0, 0, 0, 0, 0, 0, 0]), None);
        assert_eq!(parse_sockaddr_in(&[2, 0, 0]), None);
    }

    #[test]
    fn errno() {
        assert_eq!(errno_text(1), "EADDRINUSE (1)");
        assert_eq!(errno_text(999), "error (999)");
    }
}
