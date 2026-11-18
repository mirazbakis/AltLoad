// Early checks, so a problem is named before the slow steps start.

use std::io::ErrorKind;
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

use crate::ui;

/// LocalDevVPN's address for this iPhone, and remotepairingd's port.
/// Mirrors VPN_TARGET and REMOTE_PAIRING_PORT in session.rs.
const ADDR: ([u8; 4], u16) = ([10, 7, 0, 1], 49152);
const TRIES: u32 = 3;

/// Whether a connect error means the route to this iPhone is missing. A refusal
/// still means the route works (LocalDevVPN answered), so it counts as reachable.
pub fn route_missing(kind: ErrorKind) -> bool {
    !matches!(kind, ErrorKind::ConnectionRefused | ErrorKind::ConnectionReset | ErrorKind::ConnectionAborted)
}

/// Checks that LocalDevVPN routes back to this iPhone. Retries for a few
/// seconds in case it was only just connected.
pub fn check_vpn() -> Result<(), String> {
    let addr = SocketAddr::from(ADDR);
    for attempt in 1..=TRIES {
        match TcpStream::connect_timeout(&addr, Duration::from_secs(3)) {
            Ok(_) => {
                ui::debug("10.7.0.1 answers");
                return Ok(());
            }
            Err(e) if !route_missing(e.kind()) => {
                ui::debug(&format!("10.7.0.1 refused the connection ({e}); the route works"));
                return Ok(());
            }
            Err(e) => {
                ui::debug(&format!("10.7.0.1 try {attempt}: {e}"));
                if attempt < TRIES {
                    std::thread::sleep(Duration::from_secs(2));
                }
            }
        }
    }
    Err("LocalDevVPN isn't connected. Open LocalDevVPN, tap Connect, then run altpair again.".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refusals_count_as_a_route() {
        assert!(!route_missing(ErrorKind::ConnectionRefused));
        assert!(route_missing(ErrorKind::TimedOut));
        assert!(route_missing(ErrorKind::NetworkUnreachable));
        assert!(route_missing(ErrorKind::HostUnreachable));
    }
}
