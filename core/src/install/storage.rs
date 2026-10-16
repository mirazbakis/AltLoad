// Where isideload's state lives: files in Application Support/AltLoad.

use super::*;

/// isideload's state (the anisette identity and the signing certificate) kept as
/// files in Application Support/AltLoad. The Keychain used before fails with
/// errSecMissingEntitlement when AltLoad is sideloaded by signers that drop the
/// keychain-access-groups entitlement, and then sign-in can't save its
/// anisette provisioning and fails. Values saved in the Keychain by older
/// builds are still read once and moved over.
pub(super) struct FileStorage {
    dir: PathBuf,
    legacy: Option<KeyringStorage>,
}

impl FileStorage {
    pub(super) fn new(sub: &str, legacy_service: Option<&str>) -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        let dir = PathBuf::from(home)
            .join("Library/Application Support/AltLoad")
            .join(sub);
        let _ = std::fs::create_dir_all(&dir);
        Self { dir, legacy: legacy_service.map(|s| KeyringStorage::new(s.to_string())) }
    }

    fn path(&self, key: &str) -> PathBuf {
        let safe: String = key
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() || c == '.' || c == '-' || c == '_' { c } else { '_' })
            .collect();
        self.dir.join(safe)
    }
}

impl SideloadingStorage for FileStorage {
    fn store(&self, key: &str, value: &str) -> Result<(), rootcause::Report> {
        std::fs::create_dir_all(&self.dir)?;
        std::fs::write(self.path(key), value)?;
        Ok(())
    }

    fn retrieve(&self, key: &str) -> Result<Option<String>, rootcause::Report> {
        match std::fs::read_to_string(self.path(key)) {
            Ok(v) if !v.is_empty() => return Ok(Some(v)),
            Ok(_) => return Ok(None),
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e.into()),
            Err(_) => {}
        }
        // Older AltLoad builds kept this in the Keychain. Move it over if it's readable.
        let old = self.legacy.as_ref().and_then(|k| k.retrieve(key).ok().flatten());
        if let Some(v) = &old {
            let _ = std::fs::write(self.path(key), v);
        }
        Ok(old)
    }

    fn delete(&self, key: &str) -> Result<(), rootcause::Report> {
        if let Some(k) = &self.legacy {
            let _ = k.delete(key);
        }
        match std::fs::remove_file(self.path(key)) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e.into()),
            _ => Ok(()),
        }
    }
}
