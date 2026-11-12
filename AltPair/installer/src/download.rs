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

/// Downloads `url` to `dest` (through a .part file), calling `progress` with a
/// fraction when the size is known.
pub async fn fetch(
    client: &reqwest::Client,
    url: &str,
    dest: &Path,
    mut progress: impl FnMut(f64),
) -> Result<(), String> {
    let mut resp = client.get(url).send().await.map_err(|e| net_error(&e))?;
    if !resp.status().is_success() {
        return Err(format!("Download failed: HTTP {}", resp.status().as_u16()));
    }
    let total = resp.content_length().filter(|n| *n > 0);
    let part = dest.with_extension("part");
    let mut file = std::fs::File::create(&part).map_err(|e| format!("Couldn't write {}: {e}", part.display()))?;
    let mut done: u64 = 0;
    while let Some(chunk) = resp.chunk().await.map_err(|e| net_error(&e))? {
        file.write_all(&chunk).map_err(|e| format!("Couldn't write {}: {e}", part.display()))?;
        done += chunk.len() as u64;
        if let Some(total) = total {
            progress((done as f64 / total as f64).min(1.0));
        }
    }
    file.flush().map_err(|e| e.to_string())?;
    drop(file);
    if let Some(total) = total {
        if done != total {
            let _ = std::fs::remove_file(&part);
            return Err("The download ended early. Try again.".into());
        }
    }
    std::fs::rename(&part, dest).map_err(|e| format!("Couldn't save {}: {e}", dest.display()))
}

/// A short reason for a failed request, with a hint when the certificate store is missing.
pub fn net_error(e: &reqwest::Error) -> String {
    let mut text = e.to_string();
    let mut source = std::error::Error::source(e);
    while let Some(s) = source {
        text = format!("{text}: {s}");
        source = s.source();
    }
    let lower = text.to_lowercase();
    if lower.contains("certificate") || lower.contains("unknownissuer") {
        text.push_str("\nInstall CA certificates: apk add ca-certificates");
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
