//! One-line explanations for failures, with what to do next. Plain text in,
//! plain text out, so they are tested on the build machine.

/// Why no Wi-Fi address was found. `empty` means nothing arrived on stdin.
pub fn no_address(empty: bool) -> String {
    if empty {
        "No ifconfig output was read.\n\
         Run: ifconfig en0 > if.txt\n\
         then: ./altpair.wasm < if.txt\n\
         (or: ./altpair.wasm --ip A.B.C.D)"
            .into()
    } else {
        "No Wi-Fi address in that ifconfig output.\n\
         Turn on Wi-Fi (not cellular), then\n\
         run: ifconfig en0 > if.txt\n\
         and: ./altpair.wasm < if.txt"
            .into()
    }
}

/// What to do after the mDNS announcement could not be sent.
pub fn mdns(err: &str) -> String {
    let next = if err.contains("ENETUNREACH") {
        "Join Wi-Fi (not cellular) and run again."
    } else {
        "Update rootshell to 1.0.16-177 or\nlater, then run again."
    };
    format!("Couldn't announce on Wi-Fi: {err}\n{next}")
}

/// What to do after the listener could not start.
pub fn listen(err: &str) -> String {
    if err.contains("EADDRINUSE") {
        format!(
            "{err}\nAnother altpair is still running.\nClose its tab, or use --port N."
        )
    } else {
        err.to_string()
    }
}

/// What to do after the pairing exchange failed.
pub fn pairing(err: &str) -> String {
    format!(
        "pairing: {err}\n\
         Keep rootshell in front (Location\n\
         Diary Mode > Session Only), type the\n\
         PIN exactly, then run again with\n\
         --repair."
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn address_hints_differ() {
        assert!(no_address(true).contains("ifconfig en0 > if.txt"));
        assert!(no_address(false).contains("Wi-Fi"));
        assert_ne!(no_address(true), no_address(false));
    }

    #[test]
    fn mdns_points_at_rootshell_version() {
        assert!(mdns("sendto: ENOSYS (52)").contains("1.0.16-177"));
        assert!(mdns("sendto: EACCES (2)").contains("1.0.16-177"));
        assert!(mdns("sendto: ENETUNREACH (50)").contains("Wi-Fi"));
    }

    #[test]
    fn port_in_use() {
        assert!(listen("bind: EADDRINUSE (1)").contains("--port"));
        assert_eq!(listen("socket: EIO (29)"), "socket: EIO (29)");
    }

    #[test]
    fn hints_fit_40_columns() {
        for t in [no_address(true), no_address(false), mdns("x"), listen("EADDRINUSE"), pairing("x")] {
            for l in t.lines().skip(1) {
                assert!(l.chars().count() <= 40, "{l}");
            }
        }
    }
}
