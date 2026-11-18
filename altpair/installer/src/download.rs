// Getting the IPA: AltLoad's latest release by default, or a URL or file from --ipa.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const LATEST_IPA: &str = "https://github.com/mirazbakis/AltLoad/releases/latest/download/AltLoad.ipa";

#[derive(Debug, PartialEq, Eq)]
pub enum IpaSource {
    Url(String),
    Path(PathBuf),
}

/// http(s) URLs are downloaded; anything else is a local path (`file://` allowed).
pub fn ipa_source(s: &str) -> IpaSource {
    let lower = s.to_ascii_lowercase();
    if lower.starts_with("https://") || lower.starts_with("http://") {
        IpaSource::Url(s.to_string())
    } else if lower.starts_with("file://") {
        IpaSource::Path(PathBuf::from(&s["file://".len()..]))
    } else {
        IpaSource::Path(PathBuf::from(s))
    }
}

/// IPAs are zip files, which start with "PK".
pub fn looks_like_zip(path: &Path) -> Result<(), String> {
    let mut head = [0u8; 2];
    std::fs::File::open(path)
        .and_then(|mut f| f.read_exact(&mut head))
        .map_err(|e| format!("Couldn't read {}: {e}", path.display()))?;
    if &head != b"PK" {
        return Err(format!("{} is not an IPA (not a zip file).", path.display()));
    }
    Ok(())
}

pub fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .user_agent(concat!("altpair/", env!("CARGO_PKG_VERSION")))
        .connect_timeout(Duration::from_secs(15))
        .read_timeout(Duration::from_secs(60))
        .build()
        .map_err(|e| format!("Couldn't set up HTTPS: {e}"))
}

/// Tries per download, and how long to wait before each retry.
pub const ATTEMPTS: u32 = 3;

pub fn backoff(attempt: u32) -> Duration {
    Duration::from_secs(2 * u64::from(attempt) * u64::from(attempt))
}

/// Statuses worth another try: timeouts, rate limits and server errors.
pub fn is_transient_status(code: u16) -> bool {
    matches!(code, 408 | 425 | 429) || (500..600).contains(&code)
}

struct Failure {
    msg: String,
    transient: bool,
}

impl Failure {
    fn fatal(msg: String) -> Self {
        Self { msg, transient: false }
    }
    fn transient(msg: String) -> Self {
        Self { msg, transient: true }
    }
}

/// Downloads `url` to `dest` (through a .part file), calling `progress` with a
/// fraction when the size is known. Network trouble is retried up to
/// [`ATTEMPTS`] times, continuing from the bytes already saved when the server
/// allows it. `on_retry` gets the attempt that failed and why.
pub async fn fetch(
    client: &reqwest::Client,
    url: &str,
    dest: &Path,
    mut progress: impl FnMut(f64),
    mut on_retry: impl FnMut(u32, &str),
) -> Result<(), String> {
    let part = dest.with_extension("part");
    // Only resume within this run; an old .part could be from another release.
    let _ = std::fs::remove_file(&part);
    let mut attempt = 1;
    loop {
        match fetch_once(client, url, dest, &part, &mut progress).await {
            Ok(()) => return Ok(()),
            Err(f) if f.transient && attempt < ATTEMPTS => {
                on_retry(attempt, &f.msg);
                tokio::time::sleep(backoff(attempt)).await;
                attempt += 1;
            }
            Err(f) => {
                let _ = std::fs::remove_file(&part);
                return Err(f.msg);
            }
        }
    }
}

async fn fetch_once(
    client: &reqwest::Client,
    url: &str,
    dest: &Path,
    part: &Path,
    progress: &mut impl FnMut(f64),
) -> Result<(), Failure> {
    let have = std::fs::metadata(part).map(|m| m.len()).unwrap_or(0);
    let mut req = client.get(url);
    if have > 0 {
        req = req.header(reqwest::header::RANGE, format!("bytes={have}-"));
    }
    let mut resp = req.send().await.map_err(|e| Failure::transient(net_error(&e)))?;
    let status = resp.status();
    let resumed = status == reqwest::StatusCode::PARTIAL_CONTENT && have > 0;
    if status == reqwest::StatusCode::RANGE_NOT_SATISFIABLE {
        let _ = std::fs::remove_file(part);
        return Err(Failure::transient("the server couldn't continue the download".into()));
    }
    if !status.is_success() {
        let code = status.as_u16();
        let msg = if code == 404 {
            "Download failed: HTTP 404. That address has no file. Check --ipa, or try again later.".to_string()
        } else {
            format!("Download failed: HTTP {code}")
        };
        return Err(if is_transient_status(code) { Failure::transient(msg) } else { Failure::fatal(msg) });
    }
    let base = if resumed { have } else { 0 };
    let total = resp.content_length().filter(|n| *n > 0).map(|n| n + base);
    let write_err = |e: std::io::Error| Failure::fatal(format!("Couldn't write {}: {e}", part.display()));
    let mut file = if resumed {
        std::fs::OpenOptions::new().append(true).open(part)
    } else {
        std::fs::File::create(part)
    }
    .map_err(write_err)?;
    let mut done = base;
    while let Some(chunk) = resp.chunk().await.map_err(|e| Failure::transient(net_error(&e)))? {
        file.write_all(&chunk).map_err(write_err)?;
        done += chunk.len() as u64;
        if let Some(total) = total {
            progress((done as f64 / total as f64).min(1.0));
        }
    }
    file.flush().map_err(write_err)?;
    drop(file);
    if let Some(total) = total {
        if done != total {
            // Keep what arrived; the next try asks for the rest.
            return Err(Failure::transient("the download ended early".into()));
        }
    }
    std::fs::rename(part, dest).map_err(|e| Failure::fatal(format!("Couldn't save {}: {e}", dest.display())))
}

/// A short reason for a failed request, with a hint for what to do about it.
pub fn net_error(e: &reqwest::Error) -> String {
    let mut text = e.to_string();
    let mut source = std::error::Error::source(e);
    while let Some(s) = source {
        text = format!("{text}: {s}");
        source = s.source();
    }
    with_net_hint(text)
}

/// Adds what to do next for the common causes.
pub fn with_net_hint(mut text: String) -> String {
    let lower = text.to_lowercase();
    if lower.contains("certificate") || lower.contains("unknownissuer") {
        text.push_str("\nInstall CA certificates: apk add ca-certificates");
    } else if lower.contains("dns") || lower.contains("lookup") || lower.contains("resolve") {
        text.push_str("\nNo internet? Check Wi-Fi, and that LocalDevVPN isn't blocking DNS.");
    } else if lower.contains("timed out") || lower.contains("timeout") {
        text.push_str("\nThe connection is slow or down. Check Wi-Fi and try again.");
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls_and_paths() {
        assert_eq!(ipa_source("https://x.example/a.ipa"), IpaSource::Url("https://x.example/a.ipa".into()));
        assert_eq!(ipa_source("HTTP://x.example/a.ipa"), IpaSource::Url("HTTP://x.example/a.ipa".into()));
        assert_eq!(ipa_source("/root/a.ipa"), IpaSource::Path("/root/a.ipa".into()));
        assert_eq!(ipa_source("a.ipa"), IpaSource::Path("a.ipa".into()));
        assert_eq!(ipa_source("file:///root/a.ipa"), IpaSource::Path("/root/a.ipa".into()));
        assert_eq!(ipa_source("https.ipa"), IpaSource::Path("https.ipa".into()));
    }

    #[test]
    fn retry_rules() {
        assert!(is_transient_status(503));
        assert!(is_transient_status(429));
        assert!(!is_transient_status(404));
        assert!(!is_transient_status(403));
        assert!(backoff(2) > backoff(1));
        assert!(with_net_hint("dns error".into()).contains("Wi-Fi"));
        assert!(with_net_hint("invalid peer certificate".into()).contains("ca-certificates"));
        assert_eq!(with_net_hint("boom".into()), "boom");
    }

    #[test]
    fn zip_check() {
        let dir = std::env::temp_dir().join(format!("altpair-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let good = dir.join("good.ipa");
        let bad = dir.join("bad.ipa");
        std::fs::write(&good, b"PK\x03\x04rest").unwrap();
        std::fs::write(&bad, b"<html>").unwrap();
        assert!(looks_like_zip(&good).is_ok());
        assert!(looks_like_zip(&bad).is_err());
        assert!(looks_like_zip(&dir.join("missing.ipa")).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
