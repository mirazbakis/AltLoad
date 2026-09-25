// On-device sideloading for AltLoad.
//
// This is the on-device version of what AltServer does from a computer:
//   1. Open a tunnel to *this* iPhone: connect to its own `_remotepairing._tcp`
//      service with the RPPairing file created in the Pair tab, pair-verify, ask
//      it for a TCP listener, wrap that in the TLS-PSK "CDTunnel", run a
//      userspace TCP stack over it and do the RemoteServiceDiscovery handshake.
//   2. Sign in to the user's Apple ID (GrandSlam SRP + anisette headers).
//   3. Use the free developer portal API to register this device's UDID, create
//      or reuse a development certificate, register App IDs and app groups, and
//      download provisioning profiles.
//   4. Inject AltStore's runtime keys (ALTDeviceID, ALTServerID, ALTCertificate.p12,
//      ALTCertificateID, ALTAppGroups) and re-sign every bundle in the IPA.
//   5. Upload the signed .app to PublicStaging over AFC and ask
//      installation_proxy to install it. Both go through the RSD tunnel.
//
// Steps 2-5 come from `isideload` (nab138, MIT). Step 1 uses `idevice` (jkcoxson, MIT).

use std::ffi::{c_char, c_void, CStr, CString};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, Once};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use idevice::remote_pairing::{
    connect_tls_psk_tunnel_native, PeerDevice, RemotePairingClient, RpPairingFile, RpPairingSocket,
};
use idevice::rsd::RsdHandshake;
use idevice::tcp::handle::AdapterHandle;
use isideload::anisette::remote_v3::RemoteV3AnisetteProvider;
use isideload::auth::apple_account::{
    AppleAccount, TwoFactorCallbackParams, TwoFactorCallbackResponse,
};
use isideload::dev::certificates::DevelopmentCertificate;
use isideload::dev::developer_session::DeveloperSession;
use isideload::dev::device_type::DeveloperDeviceType;
use isideload::dev::devices::DevicesApi;
use isideload::sideload::builder::MaxCertsBehavior;
use isideload::sideload::{SideloaderBuilder, TeamSelection};
use isideload::util::keyring_storage::KeyringStorage;
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex as AsyncMutex};

// MARK: - C types

pub type AltLoadProgressCb =
    Option<extern "C" fn(ctx: *mut c_void, stage: *const c_char, fraction: f64)>;
pub type AltLoadPromptCb = Option<extern "C" fn(ctx: *mut c_void, kind: i32, json: *const c_char)>;

/// Prompt kinds sent to Swift. Answer each with `altload_install_session_respond`.
const PROMPT_TWO_FACTOR: i32 = 1;
const PROMPT_REVOKE_CERTS: i32 = 2;

#[repr(C)]
pub struct AltLoadEndpoint {
    pub host: *const c_char,
    pub port: u16,
    pub identifier: *const c_char,
    pub auth_tag: *const c_char,
}

#[repr(C)]
pub struct AltLoadInstallConfig {
    pub apple_id: *const c_char,
    pub password: *const c_char,
    pub anisette_url: *const c_char,
    pub pairing_file_path: *const c_char,
    pub host_name: *const c_char,
    pub endpoints: *const AltLoadEndpoint,
    pub endpoint_count: usize,
    pub ipa_path: *const c_char,
    pub device_name: *const c_char,
    pub machine_name: *const c_char,
    pub server_id: *const c_char,
}

#[repr(C)]
pub struct AltLoadInstallResult {
    pub error: *mut c_char,
    pub bundle_id: *mut c_char,
    pub app_name: *mut c_char,
    pub app_version: *mut c_char,
    pub udid: *mut c_char,
    pub team_id: *mut c_char,
    /// Provisioning profile expiry as a Unix timestamp, or 0 if unknown.
    pub expiration_unix: i64,
}

impl AltLoadInstallResult {
    fn empty() -> Self {
        Self {
            error: ptr::null_mut(),
            bundle_id: ptr::null_mut(),
            app_name: ptr::null_mut(),
            app_version: ptr::null_mut(),
            udid: ptr::null_mut(),
            team_id: ptr::null_mut(),
            expiration_unix: 0,
        }
    }
}

pub struct AltLoadInstallSession {
    responder: Mutex<Option<mpsc::UnboundedSender<String>>>,
    cancelled: AtomicBool,
}

// MARK: - Helpers

fn cstr(s: impl Into<Vec<u8>>) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

unsafe fn req(p: *const c_char, what: &str) -> Result<String, String> {
    if p.is_null() {
        return Err(format!("missing {what}"));
    }
    CStr::from_ptr(p)
        .to_str()
        .map(str::to_string)
        .map_err(|_| format!("invalid {what}"))
}

unsafe fn opt(p: *const c_char, default: &str) -> String {
    if p.is_null() {
        return default.to_string();
    }
    match CStr::from_ptr(p).to_str() {
        Ok(s) if !s.is_empty() => s.to_string(),
        _ => default.to_string(),
    }
}

fn err(prefix: &str, e: impl std::fmt::Display) -> String {
    format!("{prefix}: {e}")
}

#[derive(Clone, Copy)]
struct Callbacks {
    progress: AltLoadProgressCb,
    prompt: AltLoadPromptCb,
    ctx: *mut c_void,
}
unsafe impl Send for Callbacks {}
unsafe impl Sync for Callbacks {}

impl Callbacks {
    fn progress(&self, stage: &str, fraction: f64) {
        if let (Some(cb), Ok(c)) = (self.progress, CString::new(stage)) {
            cb(self.ctx, c.as_ptr(), fraction);
        }
    }

    fn prompt(&self, kind: i32, json: &str) {
        if let (Some(cb), Ok(c)) = (self.prompt, CString::new(json)) {
            cb(self.ctx, kind, c.as_ptr());
        }
    }
}

#[derive(Clone)]
struct Endpoint {
    host: String,
    port: u16,
    identifier: String,
    auth_tag: String,
}

struct Config {
    apple_id: String,
    password: String,
    anisette_url: String,
    pairing_file_path: String,
    host_name: String,
    endpoints: Vec<Endpoint>,
    ipa_path: String,
    device_name: String,
    machine_name: String,
    server_id: String,
}

impl Config {
    unsafe fn from_raw(c: &AltLoadInstallConfig) -> Result<Self, String> {
        let mut endpoints = Vec::new();
        if !c.endpoints.is_null() {
            for i in 0..c.endpoint_count {
                let e = &*c.endpoints.add(i);
                endpoints.push(Endpoint {
                    host: req(e.host, "endpoint host")?,
                    port: e.port,
                    identifier: opt(e.identifier, ""),
                    auth_tag: opt(e.auth_tag, ""),
                });
            }
        }
        Ok(Self {
            apple_id: req(c.apple_id, "Apple ID")?,
            password: req(c.password, "password")?,
            anisette_url: opt(c.anisette_url, "https://ani.stikstore.app"),
            pairing_file_path: req(c.pairing_file_path, "pairing file")?,
            host_name: opt(c.host_name, "AltLoad"),
            endpoints,
            ipa_path: req(c.ipa_path, "IPA path")?,
            device_name: opt(c.device_name, "iPhone"),
            machine_name: opt(c.machine_name, "AltLoad"),
            server_id: opt(c.server_id, "AltLoad"),
        })
    }
}

struct Installed {
    bundle_id: String,
    app_name: String,
    app_version: String,
    udid: String,
    team_id: String,
    expiration_unix: i64,
}

static INIT: Once = Once::new();

fn init_once() {
    INIT.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let _ = isideload::init();
    });
}

// MARK: - FFI

#[no_mangle]
pub extern "C" fn altload_install_session_new() -> *mut AltLoadInstallSession {
    Box::into_raw(Box::new(AltLoadInstallSession {
        responder: Mutex::new(None),
        cancelled: AtomicBool::new(false),
    }))
}

/// Blocking. Call it from a background thread. Progress and prompts arrive via
/// the callbacks on that same thread.
#[no_mangle]
pub unsafe extern "C" fn altload_install_session_run(
    session: *mut AltLoadInstallSession,
    config: *const AltLoadInstallConfig,
    progress_cb: AltLoadProgressCb,
    prompt_cb: AltLoadPromptCb,
    ctx: *mut c_void,
    out: *mut AltLoadInstallResult,
) -> i32 {
    if session.is_null() || config.is_null() || out.is_null() {
        return 2;
    }
    *out = AltLoadInstallResult::empty();
    init_once();

    let cfg = match Config::from_raw(&*config) {
        Ok(c) => c,
        Err(e) => {
            (*out).error = cstr(e);
            return 1;
        }
    };

    let session = &*session;
    let (tx, rx) = mpsc::unbounded_channel();
    *session.responder.lock().unwrap() = Some(tx);
    session.cancelled.store(false, Ordering::SeqCst);

    let cbs = Callbacks {
        progress: progress_cb,
        prompt: prompt_cb,
        ctx,
    };

    let rt = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            (*out).error = cstr(format!("failed to start runtime: {e}"));
            return 1;
        }
    };

    let result = rt.block_on(run_install(
        cfg,
        cbs,
        Arc::new(AsyncMutex::new(rx)),
        &session.cancelled,
    ));
    *session.responder.lock().unwrap() = None;

    match result {
        Ok(done) => {
            (*out).bundle_id = cstr(done.bundle_id);
            (*out).app_name = cstr(done.app_name);
            (*out).app_version = cstr(done.app_version);
            (*out).udid = cstr(done.udid);
            (*out).team_id = cstr(done.team_id);
            (*out).expiration_unix = done.expiration_unix;
            0
        }
        Err(e) => {
            (*out).error = cstr(e);
            1
        }
    }
}

/// Answer the prompt that is currently open.
/// Two-factor prompt: "code:123456", "sms:<id>", "devices", "resend" or "abort".
/// Certificate prompt: a JSON array of serial numbers to revoke, or "abort".
#[no_mangle]
pub unsafe extern "C" fn altload_install_session_respond(
    session: *mut AltLoadInstallSession,
    response: *const c_char,
) -> i32 {
    if session.is_null() {
        return 2;
    }
    let response = opt(response, "abort");
    match (*session).responder.lock().unwrap().as_ref() {
        Some(tx) if tx.send(response).is_ok() => 0,
        _ => 2,
    }
}

#[no_mangle]
pub unsafe extern "C" fn altload_install_session_cancel(session: *mut AltLoadInstallSession) {
    if session.is_null() {
        return;
    }
    (*session).cancelled.store(true, Ordering::SeqCst);
    // Dropping the sender makes any pending prompt resolve as "abort".
    (*session).responder.lock().unwrap().take();
}

#[no_mangle]
pub unsafe extern "C" fn altload_install_session_free(session: *mut AltLoadInstallSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

#[no_mangle]
pub unsafe extern "C" fn altload_install_result_free(r: *mut AltLoadInstallResult) {
    if r.is_null() {
        return;
    }
    for p in [
        (*r).error,
        (*r).bundle_id,
        (*r).app_name,
        (*r).app_version,
        (*r).udid,
        (*r).team_id,
    ] {
        if !p.is_null() {
            drop(CString::from_raw(p));
        }
    }
    *r = AltLoadInstallResult::empty();
}

// MARK: - Flow

type Replies = Arc<AsyncMutex<mpsc::UnboundedReceiver<String>>>;

async fn run_install(
    cfg: Config,
    cbs: Callbacks,
    replies: Replies,
    cancelled: &AtomicBool,
) -> Result<Installed, String> {
    let check = || {
        if cancelled.load(Ordering::SeqCst) {
            Err("Cancelled.".to_string())
        } else {
            Ok(())
        }
    };

    // 1. Tunnel to this device.
    cbs.progress("Connecting to this device…", -1.0);
    let (mut adapter, mut handshake) = open_tunnel(&cfg).await?;
    let udid = handshake
        .properties
        .get("UniqueDeviceID")
        .and_then(|v| v.as_string())
        .map(str::to_string)
        .ok_or("This device didn't report its UDID over RSD.")?;
    check()?;

    // 2. Unpack the IPA and add AltStore's device keys.
    cbs.progress("Preparing the app…", -1.0);
    let (work_dir, app_dir) = prepare_app(&cfg.ipa_path, &udid, &cfg.server_id)?;
    let result = sign_and_install(&cfg, cbs, replies, &check, &udid, app_dir, &mut adapter, &mut handshake).await;
    let _ = std::fs::remove_dir_all(&work_dir);
    result
}

#[allow(clippy::too_many_arguments)]
async fn sign_and_install(
    cfg: &Config,
    cbs: Callbacks,
    replies: Replies,
    check: &impl Fn() -> Result<(), String>,
    udid: &str,
    app_dir: PathBuf,
    adapter: &mut AdapterHandle,
    handshake: &mut RsdHandshake,
) -> Result<Installed, String> {
    check()?;

    // 3. Apple ID.
    cbs.progress("Signing in to Apple…", -1.0);
    let anisette = RemoteV3AnisetteProvider::default()
        .map_err(|e| err("Anisette setup failed", e))?
        .set_url(&cfg.anisette_url)
        .set_storage(Box::new(KeyringStorage::new("AltLoad.anisette".to_string())));

    let tf_replies = replies.clone();
    let two_factor = move |params: TwoFactorCallbackParams| {
        let replies = tf_replies.clone();
        let json = two_factor_json(&params);
        async move {
            cbs.prompt(PROMPT_TWO_FACTOR, &json);
            let reply = replies
                .lock()
                .await
                .recv()
                .await
                .unwrap_or_else(|| "abort".to_string());
            Ok::<_, rootcause::Report>(parse_two_factor(&reply))
        }
    };

    let mut account = AppleAccount::builder(&cfg.apple_id)
        .anisette_provider(anisette)
        .login(&cfg.password, two_factor)
        .await
        .map_err(|e| err("Apple ID sign-in failed", e))?;
    check()?;

    let dev_session = DeveloperSession::from_account(&mut account)
        .await
        .map_err(|e| err("Couldn't open a developer session", e))?;

    let cert_replies = replies.clone();
    let revoke_prompt = move |certs: Vec<DevelopmentCertificate>| {
        let replies = cert_replies.clone();
        let json = certs_json(&certs);
        async move {
            cbs.prompt(PROMPT_REVOKE_CERTS, &json);
            let reply = replies.lock().await.recv().await.unwrap_or_default();
            let serials: Vec<String> = serde_json::from_str(&reply).unwrap_or_default();
            Ok::<_, rootcause::Report>(if serials.is_empty() { None } else { Some(serials) })
        }
    };

    let mut sideloader = SideloaderBuilder::new(dev_session, cfg.apple_id.clone())
        .team_selection(TeamSelection::First)
        .max_certs_behavior(MaxCertsBehavior::Prompt(revoke_prompt))
        .storage(Box::new(KeyringStorage::new("AltLoad".to_string())))
        .machine_name(cfg.machine_name.clone())
        .delete_app_after_install(false)
        .build();

    // 4. Register this device on the team.
    cbs.progress("Registering this device…", -1.0);
    let team = sideloader
        .get_team()
        .await
        .map_err(|e| err("Couldn't load your developer team", e))?;
    sideloader
        .get_dev_session()
        .ensure_device_registered(&team, &cfg.device_name, udid, None::<DeveloperDeviceType>)
        .await
        .map_err(|e| err("Couldn't register this device", e))?;
    check()?;

    // 5. Certificates, App IDs, profiles, signing.
    cbs.progress("Signing…", 0.0);
    let sign_progress = move |f: f32| {
        cbs.progress("Signing…", f64::from(f).clamp(0.0, 1.0));
        std::future::ready(())
    };
    let (signed_dir, _special) = sideloader
        .sign_app(app_dir, Some(team.clone()), false, Some(sign_progress))
        .await
        .map_err(|e| err("Signing failed", e))?;
    check()?;

    // 6. AFC upload + installation_proxy, through the tunnel.
    cbs.progress("Installing…", 0.0);
    isideload::sideload::install::install_app_rsd(adapter, handshake, &signed_dir, move |p: u64| {
        cbs.progress("Installing…", (p as f64 / 100.0).clamp(0.0, 1.0));
    })
    .await
    .map_err(|e| err("Install failed", e))?;

    let mut installed = read_installed(&signed_dir);
    installed.udid = udid.to_string();
    if installed.team_id.is_empty() {
        installed.team_id = team.team_id.clone();
    }
    Ok(installed)
}

// MARK: - Tunnel

async fn open_tunnel(cfg: &Config) -> Result<(AdapterHandle, RsdHandshake), String> {
    let mut rpf = RpPairingFile::read_from_file(&cfg.pairing_file_path)
        .await
        .map_err(|e| err("Couldn't read the pairing file", e))?;

    // Try advertisements that prove they belong to the paired device first.
    let mut endpoints = cfg.endpoints.clone();
    if let Some(irk) = rpf.alt_irk().map(<[u8]>::to_vec) {
        endpoints.sort_by_key(|ep| !PeerDevice::validate_auth_tag(&irk, &ep.identifier, &ep.auth_tag));
    }
    if endpoints.is_empty() {
        return Err("This iPhone's pairing service wasn't found on the local network. \
                    Check that Wi-Fi is on and Developer Mode is enabled, then try again."
            .into());
    }

    let mut last_error = String::new();
    for ep in endpoints {
        match connect_endpoint(&ep, &cfg.host_name, &mut rpf).await {
            Ok(tunnel) => return Ok(tunnel),
            Err(e) => last_error = format!("{}:{}: {e}", ep.host, ep.port),
        }
    }
    Err(format!("Couldn't open a tunnel to this device ({last_error})."))
}

async fn connect_endpoint(
    ep: &Endpoint,
    host_name: &str,
    rpf: &mut RpPairingFile,
) -> Result<(AdapterHandle, RsdHandshake), String> {
    let addrs: Vec<SocketAddr> = tokio::net::lookup_host((ep.host.as_str(), ep.port))
        .await
        .map_err(|e| err("lookup", e))?
        .collect();

    let mut last = "no addresses".to_string();
    for addr in addrs {
        let stream = match tokio::time::timeout(Duration::from_secs(5), TcpStream::connect(addr)).await {
            Ok(Ok(s)) => s,
            Ok(Err(e)) => {
                last = e.to_string();
                continue;
            }
            Err(_) => {
                last = "timed out".into();
                continue;
            }
        };

        let mut rpc = RemotePairingClient::new(RpPairingSocket::new(stream), host_name);
        rpc.attempt_pair_verify()
            .await
            .map_err(|e| err("pair-verify handshake", e))?;
        // Only verify: never fall back to a fresh pair-setup here.
        rpc.validate_pairing(rpf).await.map_err(|_| {
            "this iPhone no longer accepts the pairing file. Create a new one in the Pair tab.".to_string()
        })?;

        let tunnel_port = rpc
            .create_tcp_listener()
            .await
            .map_err(|e| err("tunnel listener", e))?;
        let mut tunnel_addr = addr;
        tunnel_addr.set_port(tunnel_port);
        let tunnel_stream =
            match tokio::time::timeout(Duration::from_secs(10), TcpStream::connect(tunnel_addr)).await {
                Ok(Ok(s)) => s,
                Ok(Err(e)) => return Err(err("tunnel connect", e)),
                Err(_) => return Err("tunnel connect timed out".into()),
            };
        let tunnel = connect_tls_psk_tunnel_native(tunnel_stream, rpc.encryption_key())
            .await
            .map_err(|e| err("TLS-PSK tunnel", e))?;

        let client_ip: std::net::IpAddr = tunnel
            .info
            .client_address
            .parse()
            .map_err(|e| err("tunnel client address", e))?;
        let server_ip: std::net::IpAddr = tunnel
            .info
            .server_address
            .parse()
            .map_err(|e| err("tunnel server address", e))?;
        let mtu = tunnel.info.mtu as usize;
        let rsd_port = tunnel.info.server_rsd_port;

        let raw = tunnel.into_inner();
        let mut adapter = idevice::tcp::adapter::Adapter::new(Box::new(raw), client_ip, server_ip);
        adapter.set_mss(mtu.saturating_sub(60));
        let mut adapter = adapter.to_async_handle();

        let rsd_stream = adapter
            .connect(rsd_port)
            .await
            .map_err(|e| err("RSD connect", e))?;
        let handshake = RsdHandshake::new(rsd_stream)
            .await
            .map_err(|e| err("RSD handshake", e))?;
        return Ok((adapter, handshake));
    }
    Err(last)
}

// MARK: - Bundle prep / inspection

fn prepare_app(ipa_path: &str, udid: &str, server_id: &str) -> Result<(PathBuf, PathBuf), String> {
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

fn read_installed(app: &Path) -> Installed {
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
fn read_profile(path: &Path) -> (i64, String) {
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

// MARK: - Prompt encoding

fn two_factor_json(p: &TwoFactorCallbackParams) -> String {
    serde_json::json!({
        "unknown": p.unknown,
        "sms": p.sms,
        "lastError": p.last_error,
        "selectedNumberId": p.selected_number_id,
        "numbers": p.numbers.iter().map(|n| serde_json::json!({
            "id": n.id,
            "number": n.number_with_dial_code,
        })).collect::<Vec<_>>(),
    })
    .to_string()
}

fn parse_two_factor(reply: &str) -> TwoFactorCallbackResponse {
    let reply = reply.trim();
    if let Some(code) = reply.strip_prefix("code:") {
        return TwoFactorCallbackResponse::SubmitCode(code.trim().to_string());
    }
    if let Some(id) = reply.strip_prefix("sms:").and_then(|s| s.trim().parse::<u32>().ok()) {
        return TwoFactorCallbackResponse::SendSms(id);
    }
    match reply {
        "devices" => TwoFactorCallbackResponse::SendToDevices,
        "resend" => TwoFactorCallbackResponse::ResendCode,
        _ => TwoFactorCallbackResponse::Abort,
    }
}

fn certs_json(certs: &[DevelopmentCertificate]) -> String {
    serde_json::Value::Array(
        certs
            .iter()
            .map(|c| {
                serde_json::json!({
                    "serial": c.serial_number.clone().unwrap_or_default(),
                    "name": c.name.clone().unwrap_or_default(),
                    "machine": c.machine_name.clone().unwrap_or_default(),
                })
            })
            .collect(),
    )
    .to_string()
}
