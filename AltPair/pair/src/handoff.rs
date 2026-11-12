//! The loopback hand-off of the pairing file to the installer.
//!
//! Protocol, one exchange per TCP connection on 127.0.0.1:47627:
//!   client: `ALTLOAD-PAIR 1 <code>\n`   (at most 64 bytes including the LF)
//!   server: `OK <length>\n` + exactly `<length>` bytes of plist, then close
//!       or: `NO\n`, then close
//! After [`MAX_WRONG`] wrong requests the server gives up.

pub const PORT: u16 = 47627;
pub const MAX_LINE: usize = 64;
pub const MAX_WRONG: u32 = 5;
pub const REQUEST_PREFIX: &str = "ALTLOAD-PAIR 1 ";
pub const NO: &[u8] = b"NO\n";

/// Result of reading the request line.
#[derive(Debug, PartialEq, Eq)]
pub enum Request {
    /// A full line, without its LF.
    Line(Vec<u8>),
    /// 64 bytes arrived without an LF, or the peer closed mid-line.
    Malformed,
    /// The peer closed (or the read failed) before sending anything.
    Empty,
}

/// Reads one LF-terminated line using `recv`, which fills a buffer and returns
/// the byte count (0 at end of stream). Never reads more than [`MAX_LINE`]
/// bytes; anything after the LF is ignored.
pub fn read_request<E>(mut recv: impl FnMut(&mut [u8]) -> Result<usize, E>) -> Request {
    let mut line = Vec::with_capacity(MAX_LINE);
    let mut buf = [0u8; MAX_LINE];
    loop {
        let room = MAX_LINE - line.len();
        if room == 0 {
            return Request::Malformed;
        }
        let n = match recv(&mut buf[..room]) {
            Ok(n) => n,
            Err(_) if line.is_empty() => return Request::Empty,
            Err(_) => return Request::Malformed,
        };
        if n == 0 {
            return if line.is_empty() { Request::Empty } else { Request::Malformed };
        }
        let chunk = &buf[..n];
        if let Some(pos) = chunk.iter().position(|&b| b == b'\n') {
            line.extend_from_slice(&chunk[..pos]);
            return Request::Line(line);
        }
        line.extend_from_slice(chunk);
    }
}

/// True when `line` (without LF) is exactly `ALTLOAD-PAIR 1 <code>`.
/// A trailing CR is tolerated. The comparison does not stop at the first
/// differing byte.
pub fn is_valid_request(line: &[u8], code: &str) -> bool {
    let line = line.strip_suffix(b"\r").unwrap_or(line);
    let expected = format!("{REQUEST_PREFIX}{code}");
    let expected = expected.as_bytes();
    if line.len() != expected.len() {
        return false;
    }
    line.iter().zip(expected).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
}

/// `OK <len>\n` followed by the payload.
pub fn ok_reply(payload: &[u8]) -> Vec<u8> {
    let mut out = format!("OK {}\n", payload.len()).into_bytes();
    out.extend_from_slice(payload);
    out
}

/// Turns a stream of random `u32`s into a uniformly distributed 6-digit code
/// (leading zeros kept), discarding values that would bias the result.
pub fn code_from(mut next: impl FnMut() -> u32) -> String {
    const RANGE: u32 = 1_000_000;
    let limit = u32::MAX - (u32::MAX % RANGE);
    loop {
        let v = next();
        if v < limit {
            return format!("{:06}", v % RANGE);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Feeds `data` to `read_request` in chunks of `step` bytes.
    fn feed(data: &[u8], step: usize) -> Request {
        let mut pos = 0;
        read_request::<()>(|buf| {
            let n = step.min(buf.len()).min(data.len() - pos);
            buf[..n].copy_from_slice(&data[pos..pos + n]);
            pos += n;
            Ok(n)
        })
    }

    #[test]
    fn reads_line_in_any_chunking() {
        for step in [1, 3, 64] {
            assert_eq!(
                feed(b"ALTLOAD-PAIR 1 123456\nextra", step),
                Request::Line(b"ALTLOAD-PAIR 1 123456".to_vec())
            );
        }
    }

    #[test]
    fn line_limits() {
        // 63 bytes + LF = 64 bytes: accepted.
        let mut ok = vec![b'a'; 63];
        ok.push(b'\n');
        assert_eq!(feed(&ok, 64), Request::Line(vec![b'a'; 63]));
        // 64 bytes without LF: rejected.
        assert_eq!(feed(&[b'a'; 100], 7), Request::Malformed);
        assert_eq!(feed(b"ALTLOAD", 3), Request::Malformed);
        assert_eq!(feed(b"", 3), Request::Empty);
        assert_eq!(read_request::<()>(|_| Err(())), Request::Empty);
    }

    #[test]
    fn request_validation() {
        assert!(is_valid_request(b"ALTLOAD-PAIR 1 012345", "012345"));
        assert!(is_valid_request(b"ALTLOAD-PAIR 1 012345\r", "012345"));
        assert!(!is_valid_request(b"ALTLOAD-PAIR 1 012346", "012345"));
        assert!(!is_valid_request(b"ALTLOAD-PAIR 2 012345", "012345"));
        assert!(!is_valid_request(b"ALTLOAD-PAIR 1 012345 ", "012345"));
        assert!(!is_valid_request(b"altload-pair 1 012345", "012345"));
        assert!(!is_valid_request(b"", "012345"));
    }

    #[test]
    fn reply_framing() {
        assert_eq!(ok_reply(b"<plist/>"), b"OK 8\n<plist/>".to_vec());
        assert_eq!(ok_reply(b""), b"OK 0\n".to_vec());
        assert_eq!(NO, b"NO\n");
    }

    #[test]
    fn codes_are_six_digits_and_unbiased() {
        assert_eq!(code_from(|| 7), "000007");
        assert_eq!(code_from(|| 1_999_999), "999999");
        // Values at or above the cut-off are skipped.
        let mut vals = vec![42, u32::MAX, u32::MAX - 1].into_iter().rev();
        assert_eq!(code_from(|| vals.next().unwrap()), "000042");
    }
}
