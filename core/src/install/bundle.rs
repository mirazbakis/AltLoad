// Unpacking the IPA, AltStore's runtime keys, capabilities and reading back what was installed.

use super::*;

pub(super) fn prepare_app(ipa_path: &str, udid: &str, server_id: &str) -> Result<(PathBuf, PathBuf), String> {
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
    let app_dir = std::fs::read_dir(&payload)
        .map_err(|e| err("IPA has no Payload folder", e))?
        .filter_map(Result::ok)
        .map(|e| e.path())
        .find(|p| p.extension().is_some_and(|x| x == "app"))
        .ok_or("IPA has no .app bundle")?;

    // AltServer normally writes these. AltStore reads ALTDeviceID to know which
    // device it runs on. ALTServerID is the server it would look for to refresh.
    // AltLoad does the refreshing, so that ID is simply AltLoad's own.
    let info_path = app_dir.join("Info.plist");
    let mut info: plist::Dictionary =
        plist::from_file(&info_path).map_err(|e| err("Couldn't read Info.plist", e))?;
    info.insert("ALTDeviceID".into(), plist::Value::String(udid.to_string()));
    info.insert("ALTServerID".into(), plist::Value::String(server_id.to_string()));
    plist::to_file_binary(&info_path, &info).map_err(|e| err("Couldn't write Info.plist", e))?;

    Ok((work, app_dir))
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

    let (expiration_unix, team_id) = read_profile(&app.join("embedded.mobileprovision"));
    Installed {
        bundle_id: s("CFBundleIdentifier"),
        app_name: name,
        app_version: s("CFBundleShortVersionString"),
        udid: String::new(),
        team_id,
        expiration_unix,
    }
}

/// Pulls ExpirationDate and TeamIdentifier out of the CMS-wrapped profile plist.
pub(super) fn read_profile(path: &Path) -> (i64, String) {
    let Ok(bytes) = std::fs::read(path) else {
        return (0, String::new());
    };
    let find = |needle: &[u8]| bytes.windows(needle.len()).position(|w| w == needle);
    let (Some(start), Some(end)) = (find(b"<?xml"), find(b"</plist>")) else {
        return (0, String::new());
    };
    let Ok(dict) = plist::from_bytes::<plist::Dictionary>(&bytes[start..end + b"</plist>".len()]) else {
        return (0, String::new());
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
    (expiration, team)
}
