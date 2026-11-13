// Fetching the RemotePairing file from the pairing tool over loopback.
//
// Protocol: connect to 127.0.0.1:47627 and send `ALTLOAD-PAIR 1 <code>\n`.
// The reply is `OK <decimal byte length>\n` followed by exactly that many bytes
// (the pairing plist), or `NO\n` when the code is not accepted.

use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

pub const ADDR: ([u8; 4], u16) = ([127, 0, 0, 1], 47627);
const TIMEOUT: Duration = Duration::from_secs(10);
/// Longest header line accepted ("OK " plus a length and the newline).
const MAX_HEADER: usize = 32;
/// Pairing files are a few kilobytes; anything far larger is not one.
const MAX_BODY: usize = 1 << 20;

#[derive(Debug, PartialEq, Eq)]
pub enum Reply {
    Pairing(Vec<u8>),
    Refused,
}

/// Accepts a 6-digit code, ignoring spaces and dashes the user may type between digits.
pub fn normalize_code(input: &str) -> Option<String> {
    let code: String = input.chars().filter(|c| !matches!(c, ' ' | '-' | '\t')).collect();
    (code.len() == 6 && code.bytes().all(|b| b.is_ascii_digit())).then_some(code)
}

pub fn request_line(code: &str) -> String {
    format!("ALTLOAD-PAIR 1 {code}\n")
}

/// Reads one reply from the pairing tool.
pub fn read_reply<R: Read>(r: &mut R) -> Result<Reply, String> {
    let mut header = Vec::new();
    let mut byte = [0u8; 1];
    loop {
        match r.read(&mut byte) {
            Ok(0) => return Err("the pairing tool closed the connection".into()),
            Ok(_) if byte[0] == b'\n' => break,
            Ok(_) => {
                header.push(byte[0]);
                if header.len() > MAX_HEADER {
                    return Err("unexpected reply from the pairing tool".into());
                }
            }
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) => return Err(io_message(&e)),
        }
    }
    let header = std::str::from_utf8(&header)
        .map_err(|_| "unexpected reply from the pairing tool".to_string())?
        .trim_end_matches('\r');

    if header == "NO" {
        return Ok(Reply::Refused);
    }
    let len: usize = header
        .strip_prefix("OK ")
        .filter(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|n| n.parse().ok())
        .ok_or_else(|| "unexpected reply from the pairing tool".to_string())?;
    if len == 0 || len > MAX_BODY {
        return Err(format!("the pairing tool sent a bad length ({len})"));
    }

    let mut body = vec![0u8; len];
    r.read_exact(&mut body).map_err(|e| match e.kind() {
        std::io::ErrorKind::UnexpectedEof => "the pairing file arrived incomplete".to_string(),
        _ => io_message(&e),
    })?;
    Ok(Reply::Pairing(body))
}

/// True when the bytes are a plist (XML or binary) whose root is a dictionary.
pub fn is_plist_dictionary(bytes: &[u8]) -> bool {
    plist::Value::from_reader(std::io::Cursor::new(bytes))
        .map(|v| v.as_dictionary().is_some())
        .unwrap_or(false)
}

/// Sends the code and reads the reply, with 10 s timeouts on each part.
pub fn fetch(code: &str) -> Result<Reply, String> {
    let addr = SocketAddr::from(ADDR);
    let mut stream = TcpStream::connect_timeout(&addr, TIMEOUT).map_err(|e| match e.kind() {
        std::io::ErrorKind::ConnectionRefused => {
            "The pairing tool isn't running. Start it, then run altpair again.".to_string()
        }
        _ => io_message(&e),
    })?;
    stream.set_read_timeout(Some(TIMEOUT)).map_err(|e| io_message(&e))?;
    stream.set_write_timeout(Some(TIMEOUT)).map_err(|e| io_message(&e))?;
    stream
        .write_all(request_line(code).as_bytes())
        .and_then(|_| stream.flush())
        .map_err(|e| io_message(&e))?;
    read_reply(&mut stream)
}

fn io_message(e: &std::io::Error) -> String {
    match e.kind() {
        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut => {
            "the pairing tool didn't answer in 10 s".into()
        }
        _ => e.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn reply(bytes: &[u8]) -> Result<Reply, String> {
        read_reply(&mut Cursor::new(bytes.to_vec()))
    }

    #[test]
    fn ok_with_body() {
        assert_eq!(reply(b"OK 5\nhello"), Ok(Reply::Pairing(b"hello".to_vec())));
        // Bytes after the announced length are not read.
        assert_eq!(reply(b"OK 2\nhello"), Ok(Reply::Pairing(b"he".to_vec())));
        assert_eq!(reply(b"OK 3\r\nabc"), Ok(Reply::Pairing(b"abc".to_vec())));
    }

    #[test]
    fn refused() {
        assert_eq!(reply(b"NO\n"), Ok(Reply::Refused));
    }

    #[test]
    fn garbage() {
        for bad in [&b"HELLO\n"[..], b"OK\n", b"OK -1\n", b"OK x\n", b"OK 0\n", b"OK 99999999\n", b"no\n", b"", b"NO"] {
            assert!(reply(bad).is_err(), "{:?}", String::from_utf8_lossy(bad));
        }
        assert!(reply(&[b'A'; 100]).is_err());
    }

    #[test]
    fn short_body() {
        assert_eq!(reply(b"OK 10\nabc"), Err("the pairing file arrived incomplete".into()));
    }

    #[test]
    fn codes() {
        assert_eq!(normalize_code("123456").as_deref(), Some("123456"));
        assert_eq!(normalize_code(" 123 456\n".trim()).as_deref(), Some("123456"));
        assert_eq!(normalize_code("123-456").as_deref(), Some("123456"));
        assert_eq!(normalize_code("12345"), None);
        assert_eq!(normalize_code("1234567"), None);
        assert_eq!(normalize_code("12a456"), None);
        assert_eq!(normalize_code("١٢٣٤٥٦"), None);
        assert_eq!(request_line("123456"), "ALTLOAD-PAIR 1 123456\n");
    }

    #[test]
    fn plist_check() {
        let dict = br#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>a</key><string>b</string></dict></plist>"#;
        let array = br#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><array/></plist>"#;
        assert!(is_plist_dictionary(dict));
        assert!(!is_plist_dictionary(array));
        assert!(!is_plist_dictionary(b"not a plist"));
    }
}
