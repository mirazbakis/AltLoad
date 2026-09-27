// Device operations over the same LocalDevVPN → RemotePairing → RSD tunnel that
// installs use, without an Apple ID. They back two things:
//
//   * AltLoad's on-device AltServer. AltStore signs apps itself and only asks
//     AltServer to put them on the device and manage provisioning profiles.
//     These ops do what AltServer's ALTDeviceManager does with libimobiledevice
//     (installation_proxy, AFC, misagent), including its free-account profile
//     juggling for the 3-active-apps limit.
//   * Copying a pairing file into an installed app's container (house_arrest).
//
// One op per call; each call opens its own tunnel.

use std::collections::{HashMap, HashSet};
use std::ffi::{c_char, c_void};
use std::path::{Path, PathBuf};
use std::ptr;
use std::time::{SystemTime, UNIX_EPOCH};

use idevice::afc::opcode::AfcFopenMode;
use idevice::house_arrest::HouseArrestClient;
use idevice::installation_proxy::InstallationProxyClient;
use idevice::misagent::MisagentClient;
use idevice::rsd::RsdHandshake;
use idevice::tcp::handle::AdapterHandle;
use idevice::RsdService;

use super::{
    cstr, err, init_once, open_tunnel_to, opt, req, AltLoadInstallConfig, AltLoadProgressCb,
    Callbacks, Endpoint,
};

/// Runs one device op. `config` only needs `pairing_file_path`, `host_name` and
/// `endpoints`; the Apple ID fields are ignored.
///
/// `request_json`:
///   {"op":"install_app","path":"/…/App.ipa" | "/…/App.app","activeProfiles":["com.x",…]|null}
///   (every op also takes "protect":["com.x",…]: bundle IDs whose profiles are never
///   removed, i.e. AltLoad itself, which AltStore doesn't know about)
///   {"op":"install_profiles","paths":["/…/a.mobileprovision",…],"activeProfiles":[…]|null}
///   {"op":"remove_profiles","bundleIds":["com.x",…]}
///   {"op":"remove_app","bundleId":"com.x"}
///   {"op":"list_apps"}
///   {"op":"place_file","bundleId":"com.x","source":"/…/file","name":"Documents/File.plist"}
///
/// Returns 0 with the result JSON in `*out_json`, or 1 with an error message.
/// Free with `altload_string_free`.
#[no_mangle]
pub unsafe extern "C" fn altload_device_run(
    config: *const AltLoadInstallConfig,
    request_json: *const c_char,
    progress_cb: AltLoadProgressCb,
    ctx: *mut c_void,
    out_json: *mut *mut c_char,
) -> i32 {
    if config.is_null() || out_json.is_null() {
        return 2;
    }
    *out_json = ptr::null_mut();
    init_once();

    let fail = |msg: String| -> i32 {
        *out_json = cstr(msg);
        1
    };

    let c = &*config;
    let pairing = match req(c.pairing_file_path, "pairing file") {
        Ok(v) => v,
        Err(e) => return fail(e),
    };
    let host_name = opt(c.host_name, "AltLoad");
    let mut endpoints = Vec::new();
    if !c.endpoints.is_null() {
        for i in 0..c.endpoint_count {
            let e = &*c.endpoints.add(i);
            match req(e.host, "endpoint host") {
                Ok(host) => endpoints.push(Endpoint {
                    host,
                    port: e.port,
                    identifier: opt(e.identifier, ""),
                    auth_tag: opt(e.auth_tag, ""),
                }),
                Err(e) => return fail(e),
            }
        }
    }
    let request: serde_json::Value =
        match serde_json::from_str(&opt(request_json, "{}")) {
            Ok(v) => v,
            Err(e) => return fail(err("Bad request", e)),
        };

    let cbs = Callbacks { progress: progress_cb, prompt: None, ctx };
    let rt = match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(rt) => rt,
        Err(e) => return fail(format!("failed to start runtime: {e}")),
    };

    match rt.block_on(run(pairing, host_name, endpoints, request, cbs)) {
        Ok(json) => {
            *out_json = cstr(json.to_string());
            0
        }
        Err(e) => fail(e),
    }
}

async fn run(
    pairing: String,
    host_name: String,
    endpoints: Vec<Endpoint>,
    request: serde_json::Value,
    cbs: Callbacks,
) -> Result<serde_json::Value, String> {
    cbs.progress("Opening device link…", -1.0);
    let (mut adapter, mut handshake) = open_tunnel_to(&pairing, &host_name, &endpoints).await?;

    let op = request.get("op").and_then(|v| v.as_str()).unwrap_or_default();
    let protect = string_set(&request, "protect").unwrap_or_default();
    match op {
        "install_app" => {
            let path = string_field(&request, "path")?;
            let active = string_set(&request, "activeProfiles");
            install_app(&mut adapter, &mut handshake, Path::new(&path), active, &protect, cbs).await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "install_profiles" => {
            let paths = string_list(&request, "paths");
            let active = string_set(&request, "activeProfiles");
            let mut profiles = Vec::new();
            for p in paths {
                let data = std::fs::read(&p).map_err(|e| err("Couldn't read a profile", e))?;
                profiles.push(Profile::parse(data).ok_or("A provisioning profile couldn't be read.")?);
            }
            cbs.progress("Installing profiles…", -1.0);
            let mut mis = misagent(&mut adapter, &mut handshake).await?;
            match active {
                Some(active) => {
                    // Remove every non-active free profile, including old copies of
                    // the ones we're about to install.
                    let mut keep = active;
                    for p in &profiles {
                        keep.remove(&p.bundle_id);
                    }
                    keep.extend(protect.iter().cloned());
                    remove_profiles(&mut mis, None, Some(&keep), true).await?;
                }
                None => {
                    let ids: HashSet<String> = profiles.iter().map(|p| p.bundle_id.clone()).collect();
                    remove_profiles(&mut mis, Some(&ids), None, false).await?;
                }
            }
            for p in profiles {
                mis.install(p.data).await.map_err(|e| err("Couldn't install a profile", e))?;
            }
            Ok(serde_json::json!({ "ok": true }))
        }
        "remove_profiles" => {
            let ids: HashSet<String> = string_set(&request, "bundleIds")
                .unwrap_or_default()
                .into_iter()
                .filter(|id| !protect.contains(id))
                .collect();
            cbs.progress("Removing profiles…", -1.0);
            let mut mis = misagent(&mut adapter, &mut handshake).await?;
            remove_profiles(&mut mis, Some(&ids), None, false).await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "remove_app" => {
            let bundle_id = string_field(&request, "bundleId")?;
            cbs.progress("Removing app…", -1.0);
            let mut ip = InstallationProxyClient::connect_rsd(&mut adapter, &mut handshake)
                .await
                .map_err(|e| err("installation_proxy", e))?;
            ip.uninstall(bundle_id, None)
                .await
                .map_err(|e| err("Couldn't remove the app", e))?;
            Ok(serde_json::json!({ "ok": true }))
        }
        "list_apps" => {
            cbs.progress("Reading installed apps…", -1.0);
            let mut ip = InstallationProxyClient::connect_rsd(&mut adapter, &mut handshake)
                .await
                .map_err(|e| err("installation_proxy", e))?;
            let apps = ip
                .get_apps(Some("User"), None)
                .await
                .map_err(|e| err("Couldn't list apps", e))?;
            let mut list: Vec<serde_json::Value> = apps
                .into_iter()
                .map(|(bundle_id, info)| {
                    let d = info.as_dictionary().cloned().unwrap_or_default();
                    let s = |k: &str| d.get(k).and_then(|v| v.as_string()).unwrap_or_default().to_string();
                    let b = |k: &str| d.get(k).and_then(|v| v.as_boolean()).unwrap_or(false);
                    let name = {
                        let n = s("CFBundleDisplayName");
                        if n.is_empty() { s("CFBundleName") } else { n }
                    };
                    let debuggable = d
                        .get("Entitlements")
                        .and_then(|v| v.as_dictionary())
                        .and_then(|e| e.get("get-task-allow"))
                        .and_then(|v| v.as_boolean())
                        .unwrap_or(false);
                    serde_json::json!({
                        "bundleId": bundle_id,
                        "name": name,
                        "version": s("CFBundleShortVersionString"),
                        "fileSharing": b("UIFileSharingEnabled"),
                        "debuggable": debuggable,
                    })
                })
                .collect();
            list.sort_by(|a, b| {
                a["name"].as_str().unwrap_or("").to_lowercase().cmp(&b["name"].as_str().unwrap_or("").to_lowercase())
            });
            Ok(serde_json::Value::Array(list))
        }
        "place_file" => {
            let bundle_id = string_field(&request, "bundleId")?;
            let source = string_field(&request, "source")?;
            let name = string_field(&request, "name")?;
            cbs.progress("Copying the file into the app…", -1.0);
            place_file(&mut adapter, &mut handshake, &bundle_id, Path::new(&source), &name).await?;
            Ok(serde_json::json!({ "ok": true }))
        }
        other => Err(format!("Unknown device op \"{other}\".")),
    }
}

// MARK: - Install (AltServer's installAppAtURL)

async fn install_app(
    adapter: &mut AdapterHandle,
    handshake: &mut RsdHandshake,
    path: &Path,
    active: Option<HashSet<String>>,
    protect: &HashSet<String>,
    cbs: Callbacks,
) -> Result<(), String> {
    cbs.progress("Preparing the app…", -1.0);
    let (work, app_dir) = if path.extension().is_some_and(|x| x.eq_ignore_ascii_case("app")) {
        (None, path.to_path_buf())
    } else {
        let (work, app) = unpack(path)?;
        (Some(work), app)
    };

    let result = install_unpacked(adapter, handshake, &app_dir, active, protect, cbs).await;
    if let Some(work) = work {
        let _ = std::fs::remove_dir_all(work);
    }
    result
}

async fn install_unpacked(
    adapter: &mut AdapterHandle,
    handshake: &mut RsdHandshake,
    app_dir: &Path,
    active: Option<HashSet<String>>,
    protect: &HashSet<String>,
    cbs: Callbacks,
) -> Result<(), String> {
    // Profiles that come with the app and its extensions.
    let installed_profiles: Vec<Profile> = bundle_profiles(app_dir);
    let main_is_free = std::fs::read(app_dir.join("embedded.mobileprovision"))
        .ok()
        .and_then(Profile::parse)
        .is_some_and(|p| p.free);

    // Free Apple IDs may only have 3 apps' profiles on the device, so, like
    // AltServer, take every free profile off first and put the active ones back after.
    let mut cached: HashMap<String, Profile> = HashMap::new();
    if active.is_some() || main_is_free {
        cbs.progress("Making room for the app…", -1.0);
        let mut mis = misagent(adapter, handshake).await?;
        // `protect` (AltLoad itself) stays: AltStore's active list doesn't include it.
        let removed = remove_profiles(&mut mis, None, Some(protect), true).await?;
        for (bundle_id, profile) in removed {
            if active.as_ref().map_or(true, |a| a.contains(&bundle_id)) {
                cached.insert(bundle_id, profile);
            }
        }
    }

    cbs.progress("Installing…", 0.0);
    let install = isideload::sideload::install::install_app_rsd(adapter, handshake, app_dir, move |p: u64| {
        cbs.progress("Installing…", (p as f64 / 100.0).clamp(0.0, 1.0));
    })
    .await
    .map_err(|e| err("Install failed", e));

    // Put things back even if the install failed.
    let mut mis = misagent(adapter, handshake).await?;
    if let Some(active) = &active {
        for p in &installed_profiles {
            if !active.contains(&p.bundle_id) {
                let _ = mis.remove(&p.uuid).await;
            }
        }
    }
    let mut restore_error = None;
    for (bundle_id, profile) in cached {
        if installed_profiles.iter().any(|p| p.bundle_id == bundle_id) {
            continue; // Installed with the app.
        }
        if let Err(e) = mis.install(profile.data).await {
            restore_error.get_or_insert(err("Couldn't reinstall a provisioning profile", e));
        }
    }

    install?;
    match restore_error {
        Some(e) => Err(e),
        None => Ok(()),
    }
}

fn unpack(ipa: &Path) -> Result<(PathBuf, PathBuf), String> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or_default();
    let work = std::env::temp_dir().join(format!("altserver-{stamp}"));
    std::fs::create_dir_all(&work).map_err(|e| err("temp dir", e))?;
    let file = std::fs::File::open(ipa).map_err(|e| err("Couldn't open the app", e))?;
    let mut archive = zip::ZipArchive::new(file).map_err(|e| err("Not a valid IPA", e))?;
    archive.extract(&work).map_err(|e| err("Couldn't unpack the app", e))?;
    let app = std::fs::read_dir(work.join("Payload"))
        .map_err(|e| err("IPA has no Payload folder", e))?
        .filter_map(Result::ok)
        .map(|e| e.path())
        .find(|p| p.extension().is_some_and(|x| x == "app"))
        .ok_or("IPA has no .app bundle")?;
    Ok((work, app))
}

/// embedded.mobileprovision of the app and every .appex inside it.
fn bundle_profiles(app: &Path) -> Vec<Profile> {
    let mut out = Vec::new();
    let mut stack = vec![app.to_path_buf()];
    while let Some(dir) = stack.pop() {
        if let Some(p) = std::fs::read(dir.join("embedded.mobileprovision")).ok().and_then(Profile::parse) {
            out.push(p);
        }
        for sub in ["PlugIns", "Extensions"] {
            if let Ok(entries) = std::fs::read_dir(dir.join(sub)) {
                for e in entries.filter_map(Result::ok) {
                    let path = e.path();
                    if path.extension().is_some_and(|x| x == "appex") {
                        stack.push(path);
                    }
                }
            }
        }
    }
    out
}

// MARK: - Provisioning profiles (misagent)

struct Profile {
    data: Vec<u8>,
    uuid: String,
    /// application-identifier without the team prefix, e.g. "com.x.TEAMID".
    bundle_id: String,
    /// LocalProvision: made for a free Apple ID.
    free: bool,
    expires: i64,
}

impl Profile {
    fn parse(data: Vec<u8>) -> Option<Self> {
        let find = |needle: &[u8]| data.windows(needle.len()).position(|w| w == needle);
        let start = find(b"<?xml")?;
        let end = find(b"</plist>")? + b"</plist>".len();
        let dict: plist::Dictionary = plist::from_bytes(&data[start..end]).ok()?;
        let uuid = dict.get("UUID")?.as_string()?.to_string();
        let app_id = dict
            .get("Entitlements")
            .and_then(|v| v.as_dictionary())
            .and_then(|e| e.get("application-identifier"))
            .and_then(|v| v.as_string())
            .unwrap_or_default();
        let bundle_id = app_id.split_once('.').map(|(_, rest)| rest.to_string()).unwrap_or_default();
        let free = dict.get("LocalProvision").and_then(|v| v.as_boolean()).unwrap_or(false);
        let expires = dict
            .get("ExpirationDate")
            .and_then(|v| v.as_date())
            .and_then(|d| SystemTime::from(d).duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        Some(Self { data, uuid, bundle_id, free, expires })
    }
}

async fn misagent(adapter: &mut AdapterHandle, handshake: &mut RsdHandshake) -> Result<MisagentClient, String> {
    MisagentClient::connect_rsd(adapter, handshake)
        .await
        .map_err(|e| err("Couldn't reach misagent", e))
}

/// AltServer's removeAllProfilesForBundleIdentifiers:excludingBundleIdentifiers:limitedToFreeProfiles:.
/// Returns the newest removed profile per bundle ID, so callers can put some back.
async fn remove_profiles(
    mis: &mut MisagentClient,
    include: Option<&HashSet<String>>,
    exclude: Option<&HashSet<String>>,
    free_only: bool,
) -> Result<HashMap<String, Profile>, String> {
    let all = mis
        .copy_all()
        .await
        .map_err(|e| err("Couldn't list provisioning profiles", e))?;

    let mut kept: HashMap<String, Profile> = HashMap::new();
    let mut removed: HashMap<String, Profile> = HashMap::new();

    for profile in all.into_iter().filter_map(Profile::parse) {
        if free_only && !profile.free {
            continue;
        }
        if include.is_some_and(|ids| !ids.contains(&profile.bundle_id)) {
            continue;
        }
        if exclude.is_some_and(|ids| ids.contains(&profile.bundle_id)) {
            // Keep only the newest excluded profile per bundle ID.
            match kept.remove(&profile.bundle_id) {
                Some(previous) => {
                    let (newest, oldest) = if profile.expires > previous.expires {
                        (profile, previous)
                    } else {
                        (previous, profile)
                    };
                    mis.remove(&oldest.uuid)
                        .await
                        .map_err(|e| err("Couldn't remove a provisioning profile", e))?;
                    kept.insert(newest.bundle_id.clone(), newest);
                }
                None => {
                    kept.insert(profile.bundle_id.clone(), profile);
                }
            }
            continue;
        }

        mis.remove(&profile.uuid)
            .await
            .map_err(|e| err("Couldn't remove a provisioning profile", e))?;
        let newer = removed
            .get(&profile.bundle_id)
            .map_or(true, |p| profile.expires > p.expires);
        if newer {
            removed.insert(profile.bundle_id.clone(), profile);
        }
    }
    Ok(removed)
}

// MARK: - Files into an app (house_arrest)

async fn place_file(
    adapter: &mut AdapterHandle,
    handshake: &mut RsdHandshake,
    bundle_id: &str,
    source: &Path,
    name: &str,
) -> Result<(), String> {
    let data = std::fs::read(source).map_err(|e| err("Couldn't read the file", e))?;
    let name = name.trim_start_matches('/');

    // The whole container works for apps signed with a development profile
    // (everything AltLoad, AltStore or Catalyst installs). Documents-only access
    // is the fallback for apps with file sharing turned on.
    let container = match HouseArrestClient::connect_rsd(adapter, handshake).await {
        Ok(client) => client.vend_container(bundle_id).await,
        Err(e) => Err(e),
    };
    let mut afc = match container {
        Ok(afc) => afc,
        Err(container_error) => {
            let documents = match HouseArrestClient::connect_rsd(adapter, handshake).await {
                Ok(client) => client.vend_documents(bundle_id).await,
                Err(e) => Err(e),
            };
            documents.map_err(|e| {
                format!(
                    "iOS won't let AltLoad into this app ({container_error}; {e}). Only apps signed \
                     with a development certificate, or with file sharing on, can receive files."
                )
            })?
        }
    };
    let path = format!("/{name}");

    if let Some(parent) = Path::new(&path).parent().and_then(|p| p.to_str()) {
        if parent != "/" && !parent.is_empty() {
            let _ = afc.mk_dir(parent).await;
        }
    }
    let mut file = afc
        .open(path.clone(), AfcFopenMode::WrOnly)
        .await
        .map_err(|e| err("Couldn't create the file in the app", e))?;
    file.write_entire(&data)
        .await
        .map_err(|e| err("Couldn't write the file", e))?;
    file.close().await.map_err(|e| err("Couldn't finish writing", e))?;
    Ok(())
}

// MARK: - JSON helpers

fn string_field(v: &serde_json::Value, key: &str) -> Result<String, String> {
    v.get(key)
        .and_then(|x| x.as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .ok_or_else(|| format!("missing {key}"))
}

fn string_list(v: &serde_json::Value, key: &str) -> Vec<String> {
    v.get(key)
        .and_then(|x| x.as_array())
        .map(|a| a.iter().filter_map(|s| s.as_str().map(str::to_string)).collect())
        .unwrap_or_default()
}

/// `None` when the key is missing or null (AltStore's "don't manage profiles").
fn string_set(v: &serde_json::Value, key: &str) -> Option<HashSet<String>> {
    v.get(key).and_then(|x| x.as_array()).map(|a| a.iter().filter_map(|s| s.as_str().map(str::to_string)).collect())
}
