// Unpacking the IPA, AltStore's runtime keys, capabilities and reading back what was installed.

use super::*;

/// Unzips the IPA into a fresh temp dir and finds the .app inside it.
/// Returns `(work_dir, app_dir)`; the caller removes `work_dir` when done.
pub(super) fn unpack_ipa(ipa_path: &str) -> Result<(PathBuf, PathBuf), String> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let work = std::env::temp_dir().join(format!("altload-{stamp}"));
    std::fs::create_dir_all(&work).map_err(|e| err("temp dir", e))?;

    let file = std::fs::File::open(ipa_path).map_err(|e| err("Couldn't open the IPA", e))?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| err("Not a valid IPA", e))?;
    archive
        .extract(&work)
        .map_err(|e| err("Couldn't unpack the IPA", e))?;

    let payload = work.join("Payload");
    let found = std::fs::read_dir(&payload)
        .map_err(|e| err("IPA has no Payload folder", e))
        .and_then(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|e| e.path())
                .find(|p| p.extension().is_some_and(|x| x == "app"))
                .ok_or_else(|| "IPA has no .app bundle".to_string())
        });
    match found {
        Ok(app_dir) => Ok((work, app_dir)),
        Err(e) => {
            let _ = std::fs::remove_dir_all(&work);
            Err(e)
        }
    }
}

/// Writes the device keys AltStore reads from the app's Info.plist.
pub(super) fn stamp_app(app_dir: &Path, udid: &str, server_id: &str) -> Result<(), String> {
    // AltServer normally writes these. AltStore reads ALTDeviceID to know which
    // device it runs on. ALTServerID is the server it would look for to refresh.
    // AltLoad does the refreshing, so that ID is simply AltLoad's own.
    let info_path = app_dir.join("Info.plist");
    let mut info: plist::Dictionary =
        plist::from_file(&info_path).map_err(|e| err("Couldn't read Info.plist", e))?;
    info.insert("ALTDeviceID".into(), plist::Value::String(udid.to_string()));
    info.insert("ALTServerID".into(), plist::Value::String(server_id.to_string()));
    plist::to_file_binary(&info_path, &info).map_err(|e| err("Couldn't write Info.plist", e))?;

    Ok(())
}

pub(super) const ALTSTORE_BETA_BUNDLE_ID: &str = "com.rileytestut.AltStore.Beta";

pub(super) fn bundle_id_of(app: &Path) -> String {
    plist::from_file::<_, plist::Dictionary>(app.join("Info.plist"))
        .ok()
        .and_then(|info| info.get("CFBundleIdentifier").and_then(|v| v.as_string()).map(str::to_string))
        .unwrap_or_default()
}

/// Enables `capabilities` (App Store Connect capability IDs) on the App ID that
/// `sign_app` will use for this bundle, creating the App ID if it doesn't exist yet.
/// Same JSON:API call isideload makes for INCREASED_MEMORY_LIMIT, one capability
/// at a time so the error names the one Apple refused (paid-only ones fail on a
/// free Apple ID).
pub(super) async fn enable_capabilities(
    dev: &mut DeveloperSession,
    team: &DeveloperTeam,
    app: &Path,
    capabilities: &[String],
) -> Result<(), String> {
    let bundle_id = bundle_id_of(app);
    if bundle_id.is_empty() {
        return Err("Couldn't read the app's bundle ID.".into());
    }
    // sign_app registers the main app as <bundle id>.<team id>.
    let identifier = format!("{bundle_id}.{}", team.team_id);
    let name = plist::from_file::<_, plist::Dictionary>(app.join("Info.plist"))
        .ok()
        .and_then(|info| {
            info.get("CFBundleDisplayName")
                .or_else(|| info.get("CFBundleName"))
                .and_then(|v| v.as_string())
                .map(str::to_string)
        })
        .unwrap_or_else(|| bundle_id.clone());

    let existing = dev
        .list_app_ids(team, None::<DeveloperDeviceType>)
        .await
        .map_err(|e| err("Couldn't list App IDs", e))?;
    let app_id = match existing.app_ids.into_iter().find(|a| a.identifier == identifier) {
        Some(app_id) => app_id,
        None => dev
            .add_app_id(team, &name, &identifier, None::<DeveloperDeviceType>)
            .await
            .map_err(|e| err("Couldn't register the App ID", e))?,
    };

    for capability in capabilities {
        let body = serde_json::json!({
            "data": {
                "type": "bundleIds",
                "id": app_id.app_id_id,
                "attributes": {
                    "identifier": app_id.identifier,
                    "seedId": team.team_id,
                    "teamId": team.team_id,
                    "name": app_id.name,
                    "bundleType": "bundle",
                    "hasExclusiveManagedCapabilities": false
                },
                "relationships": {
                    "bundleIdCapabilities": {
                        "data": [{
                            "type": "bundleIdCapabilities",
                            "attributes": { "enabled": true, "settings": [] },
                            "relationships": {
                                "capability": { "data": { "type": "capabilities", "id": capability } }
                            }
                        }]
                    }
                }
            }
        });

        let mut headers = dev
            .get_headers()
            .await
            .map_err(|e| err("Couldn't get anisette headers", e))?;
        headers.insert("Content-Type", "application/vnd.api+json".parse().expect("static header"));
        headers.insert("Accept", "application/vnd.api+json".parse().expect("static header"));

        let url = format!(
            "https://developerservices2.apple.com/services/v1/bundleIds/{}",
            app_id.app_id_id
        );
        let response = dev
            .get_grandslam_client()
            .patch(&url)
            .map_err(|e| err("Couldn't build the request", e))?
            .headers(headers)
            .body(body.to_string())
            .send()
            .await
            .map_err(|e| err(&format!("Couldn't enable {capability}"), e))?;
        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            let detail = serde_json::from_str::<serde_json::Value>(&text)
                .ok()
                .and_then(|v| v["errors"][0]["detail"].as_str().map(str::to_string))
                .unwrap_or_else(|| format!("HTTP {status}"));
            return Err(format!(
                "Apple wouldn't enable {capability}: {detail}\n\nSome entitlements need a paid Apple Developer account. Turn it off in Tools › Entitlements and try again."
            ));
        }
    }
    Ok(())
}

/// What isideload's `apply_special_app_behavior` writes for AltStore:
/// ALTAppGroups (the group isideload registers, `group.<bundle id>.<team>`),
/// ALTCertificateID and ALTCertificate.p12 (password: the certificate's machine ID).
/// Runs before `sign_app`, which reads the bundle from disk, so it all gets signed.
pub(super) async fn inject_store_keys(app: &Path, bundle_id: &str, team_id: &str, cert: &CertificateIdentity) -> Result<(), String> {
    let info_path = app.join("Info.plist");
    let mut info: plist::Dictionary =
        plist::from_file(&info_path).map_err(|e| err("Couldn't read Info.plist", e))?;
    let group = format!("group.{bundle_id}.{team_id}");
    info.insert(
        "ALTAppGroups".into(),
        plist::Value::Array(vec![plist::Value::String(group)]),
    );
    info.insert(
        "ALTCertificateID".into(),
        plist::Value::String(cert.get_serial_number()),
    );
    plist::to_file_binary(&info_path, &info).map_err(|e| err("Couldn't write Info.plist", e))?;

    let p12 = cert
        .as_p12(&cert.machine_id)
        .await
        .map_err(|e| err("Couldn't export the certificate", e))?;
    std::fs::write(app.join("ALTCertificate.p12"), p12)
        .map_err(|e| err("Couldn't write ALTCertificate.p12", e))?;
    Ok(())
}

/// Where AltStore reads its pairing file: `ALTPairingFile.dat` in the bundle.
const ALT_PAIRING_FILE: &str = "ALTPairingFile.dat";

/// The pairing file AltStore gets, with this iPhone's UDID in it, as the other
/// stores' copies have. None when it can't be read.
pub(super) fn pairing_for_altstore(path: &str, udid: &str) -> Option<Vec<u8>> {
    let raw = std::fs::read(path).ok()?;
    Some(with_udid(&raw, udid).unwrap_or(raw))
}

/// None when the file isn't a property list dictionary, or already names a UDID.
fn with_udid(raw: &[u8], udid: &str) -> Option<Vec<u8>> {
    let mut record: plist::Dictionary = plist::from_bytes(raw).ok()?;
    let named = record.get("UDID").and_then(|v| v.as_string()).is_some_and(|s| !s.is_empty());
    if named || udid.is_empty() {
        return None;
    }
    record.insert("UDID".into(), plist::Value::String(udid.to_string()));
    let mut out = Vec::new();
    plist::to_writer_xml(&mut out, &record).ok()?;
    Some(out)
}

/// What isideload's `apply_special_app_behavior` writes for AltStore's pairing file,
/// for AltStore Beta: the nonce, then the file under AES-256-GCM, keyed with the
/// SHA-256 of the certificate's machine ID. Runs before `sign_app`, so it gets signed.
pub(super) fn seal_pairing_file(app: &Path, cert: &CertificateIdentity, pairing: &[u8]) -> Result<(), String> {
    let sealed = seal(cert.machine_id.as_bytes(), pairing)?;
    std::fs::write(app.join(ALT_PAIRING_FILE), sealed)
        .map_err(|e| err("Couldn't write the pairing file for AltStore", e))
}

fn seal(secret: &[u8], data: &[u8]) -> Result<Vec<u8>, String> {
    use aes_gcm::{aead::{Aead, Generate}, Aes256Gcm, KeyInit, Nonce};
    use sha2::{Digest, Sha256};

    let key = Sha256::digest(secret);
    let cipher = Aes256Gcm::new(&key);
    let nonce = Nonce::generate();
    let ciphertext = cipher
        .encrypt(&nonce, data)
        .map_err(|e| err("Couldn't seal the pairing file for AltStore", e))?;
    let mut sealed = Vec::with_capacity(nonce.len() + ciphertext.len());
    sealed.extend_from_slice(&nonce);
    sealed.extend_from_slice(&ciphertext);
    Ok(sealed)
}

pub(super) fn read_installed(app: &Path) -> Installed {
    let info: plist::Dictionary = plist::from_file(app.join("Info.plist")).unwrap_or_default();
    let s = |k: &str| {
        info.get(k)
            .and_then(|v| v.as_string())
            .unwrap_or_default()
            .to_string()
    };
    let name = {
        let d = s("CFBundleDisplayName");
        if d.is_empty() { s("CFBundleName") } else { d }
    };

    let (expiration_unix, team_id, certificates) = read_profile(&app.join("embedded.mobileprovision"));
    Installed {
        bundle_id: s("CFBundleIdentifier"),
        app_name: name,
        app_version: s("CFBundleShortVersionString"),
        udid: String::new(),
        team_id,
        expiration_unix,
        certificates,
    }
}

/// Pulls ExpirationDate and TeamIdentifier out of the CMS-wrapped profile plist.
/// Expiry, team and developer certificates (DER in hex, comma-separated) of a
/// provisioning profile.
pub(super) fn read_profile(path: &Path) -> (i64, String, String) {
    let Ok(bytes) = std::fs::read(path) else {
        return (0, String::new(), String::new());
    };
    let find = |needle: &[u8]| bytes.windows(needle.len()).position(|w| w == needle);
    let (Some(start), Some(end)) = (find(b"<?xml"), find(b"</plist>")) else {
        return (0, String::new(), String::new());
    };
    let Ok(dict) = plist::from_bytes::<plist::Dictionary>(&bytes[start..end + b"</plist>".len()]) else {
        return (0, String::new(), String::new());
    };
    let expiration = dict
        .get("ExpirationDate")
        .and_then(|v| v.as_date())
        .and_then(|d| SystemTime::from(d).duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let team = dict
        .get("TeamIdentifier")
        .and_then(|v| v.as_array())
        .and_then(|a| a.first())
        .and_then(|v| v.as_string())
        .unwrap_or_default()
        .to_string();
    let certificates = dict
        .get("DeveloperCertificates")
        .and_then(|v| v.as_array())
        .map(|certs| {
            certs
                .iter()
                .filter_map(|c| c.as_data())
                .map(|der| der.iter().map(|b| format!("{b:02x}")).collect::<String>())
                .collect::<Vec<_>>()
                .join(",")
        })
        .unwrap_or_default();
    (expiration, team, certificates)
}

#[cfg(test)]
mod pairing_tests {
    use super::*;

    #[test]
    fn the_sealed_file_opens_with_the_machine_id() {
        use aes_gcm::{aead::Aead, Aes256Gcm, KeyInit, Nonce};
        use sha2::{Digest, Sha256};

        let sealed = seal(b"machine", b"pairing").unwrap();
        let (nonce, ciphertext) = sealed.split_at(12);
        let cipher = Aes256Gcm::new(&Sha256::digest(b"machine"));
        let nonce = Nonce::try_from(nonce).unwrap();
        assert_eq!(cipher.decrypt(&nonce, ciphertext).unwrap(), b"pairing");
        assert!(Aes256Gcm::new(&Sha256::digest(b"other")).decrypt(&nonce, ciphertext).is_err());
    }

    #[test]
    fn the_udid_is_added_only_when_missing() {
        let mut record = plist::Dictionary::new();
        record.insert("identifier".into(), plist::Value::String("host".into()));
        let mut raw = Vec::new();
        plist::to_writer_xml(&mut raw, &record).unwrap();

        let added: plist::Dictionary = plist::from_bytes(&with_udid(&raw, "0000-A").unwrap()).unwrap();
        assert_eq!(added["UDID"].as_string(), Some("0000-A"));
        assert_eq!(added["identifier"].as_string(), Some("host"));

        let mut named = Vec::new();
        plist::to_writer_xml(&mut named, &added).unwrap();
        assert!(with_udid(&named, "0000-B").is_none());
        assert!(with_udid(b"not a plist", "0000-A").is_none());
    }
}
