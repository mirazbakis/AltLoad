// On-device sideloading for AltLoad.
//
// This is the on-device version of what AltServer does from a computer:
//   1. Sign in to the user's Apple ID (GrandSlam SRP + anisette headers), falling
//      back to the next anisette server when Apple rejects one.
//   2. Open a tunnel to *this* iPhone: through LocalDevVPN (which reflects packets
//      sent to 10.7.0.1 back into the device), connect to its own RemotePairing
//      service on port 49152 with the RPPairing file from the Pair tab, pair-verify, ask
//      it for a TCP listener, wrap that in the TLS-PSK "CDTunnel", run a
//      userspace TCP stack over it and do the RemoteServiceDiscovery handshake.
//   3. Use the free developer portal API to register this device's UDID, create
//      or reuse a development certificate, register App IDs and app groups, and
//      download provisioning profiles.
//   4. Enable any capabilities the user picked on the App ID (so the profile grants
//      their entitlements), inject AltStore's runtime keys (ALTDeviceID, ALTServerID,
//      ALTCertificate.p12, ALTCertificateID, ALTAppGroups) and re-sign every bundle.
//   5. Upload the signed .app to PublicStaging over AFC and ask
//      installation_proxy to install it. Both go through the RSD tunnel.
//
// AltStore Beta (com.rileytestut.AltStore.Beta) gets the step-4 keys isideload only
// adds for the exact AltStore bundle ID; see `inject_store_keys`.
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
use isideload::dev::app_ids::AppIdsApi;
use isideload::dev::certificates::{CertificatesApi, DevelopmentCertificate};
use isideload::dev::developer_session::DeveloperSession;
use isideload::dev::device_type::DeveloperDeviceType;
use isideload::dev::devices::DevicesApi;
use isideload::dev::teams::{DeveloperTeam, TeamsApi};
use isideload::sideload::builder::MaxCertsBehavior;
use isideload::sideload::application::SpecialApp;
use isideload::sideload::cert_identity::CertificateIdentity;
use isideload::sideload::{SideloaderBuilder, TeamSelection};
use isideload::util::keyring_storage::KeyringStorage;
use isideload::util::storage::SideloadingStorage;
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex as AsyncMutex};

mod account;
mod bundle;
mod device;
mod extensions;
mod prompts;
mod sign_in;
mod storage;
mod tunnel;

use bundle::*;
use extensions::*;
use prompts::*;
use sign_in::*;
use storage::*;
use tunnel::*;

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
    /// Comma-separated capability IDs to enable on the App ID, or null.
    pub capabilities: *const c_char,
    /// App extensions: 0 keep, 1 keep and sign with the main profile, 2 remove.
    pub extensions_mode: i32,
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
    capabilities: Vec<String>,
    extensions: ExtensionsMode,
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
            anisette_url: opt(c.anisette_url, "https://ani.jkcoxson.com"),
            pairing_file_path: req(c.pairing_file_path, "pairing file")?,
            host_name: opt(c.host_name, "AltLoad"),
            endpoints,
            ipa_path: req(c.ipa_path, "IPA path")?,
            device_name: opt(c.device_name, "iPhone"),
            machine_name: opt(c.machine_name, "AltLoad"),
            server_id: opt(c.server_id, "AltLoad"),
            capabilities: opt(c.capabilities, "")
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect(),
            extensions: ExtensionsMode::from_raw(c.extensions_mode),
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

    // 1. Apple ID first, so a sign-in problem shows up straight away instead of
    // after the device link, and 2FA is done before anything touches the device.
    cbs.progress("Signing in to Apple…", -1.0);
    let dev_session = sign_in(&cfg.apple_id, &cfg.password, &cfg.anisette_url, cbs, replies.clone()).await?;
    check()?;

    // 2. Tunnel to this device.
    cbs.progress("Connecting to this device…", -1.0);
    let (mut adapter, mut handshake) = open_tunnel(&cfg).await?;
    let udid = handshake
        .properties
        .get("UniqueDeviceID")
        .and_then(|v| v.as_string())
        .map(str::to_string)
        .ok_or("This device didn't report its UDID over RSD.")?;
    check()?;

    // 3. Unpack the IPA and add AltStore's device keys.
    cbs.progress("Preparing the app…", -1.0);
    let (work_dir, app_dir) = prepare_app(&cfg.ipa_path, &udid, &cfg.server_id)?;
    let result = sign_and_install(&cfg, dev_session, cbs, replies, &check, &udid, app_dir, &mut adapter, &mut handshake).await;
    let _ = std::fs::remove_dir_all(&work_dir);
    result
}

#[allow(clippy::too_many_arguments)]
async fn sign_and_install(
    cfg: &Config,
    dev_session: DeveloperSession,
    cbs: Callbacks,
    replies: Replies,
    check: &impl Fn() -> Result<(), String>,
    udid: &str,
    app_dir: PathBuf,
    adapter: &mut AdapterHandle,
    handshake: &mut RsdHandshake,
) -> Result<Installed, String> {
    check()?;

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
        .max_certs_behavior(MaxCertsBehavior::Prompt(revoke_prompt.clone()))
        .storage(Box::new(FileStorage::new("signing", Some("AltLoad"))))
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

    // 4b. isideload only recognises AltStore by its exact bundle ID. AltStore Beta
    // needs the same keys: the certificate (so it refreshes apps with it instead of
    // making a new one) and its app group.
    if bundle_id_of(&app_dir) == ALTSTORE_BETA_BUNDLE_ID {
        cbs.progress("Preparing AltStore Beta…", -1.0);
        let storage = FileStorage::new("signing", Some("AltLoad"));
        let cert = CertificateIdentity::retrieve(
            &cfg.machine_name,
            &cfg.apple_id,
            sideloader.get_dev_session(),
            &team,
            &storage,
            &MaxCertsBehavior::Prompt(revoke_prompt.clone()),
        )
        .await
        .map_err(|e| err("Couldn't get a signing certificate", e))?;
        inject_store_keys(&app_dir, ALTSTORE_BETA_BUNDLE_ID, &team.team_id, &cert).await?;
        check()?;
    }

    // 4c. Capabilities the user switched on. Enabled on the App ID before signing,
    // so the provisioning profile sign_app downloads grants their entitlements.
    if !cfg.capabilities.is_empty() {
        cbs.progress("Enabling entitlements…", -1.0);
        enable_capabilities(sideloader.get_dev_session(), &team, &app_dir, &cfg.capabilities).await?;
        check()?;
    }

    // 5. Certificates, App IDs, profiles, signing.
    cbs.progress("Signing…", 0.0);
    if cfg.extensions == ExtensionsMode::Remove {
        remove_extensions(&app_dir)?;
    }
    let signed_dir = if cfg.extensions == ExtensionsMode::MainProfile {
        let storage = FileStorage::new("signing", Some("AltLoad"));
        sign_with_main_profile(
            sideloader.get_dev_session(),
            &team,
            &cfg.apple_id,
            &cfg.machine_name,
            &storage,
            &MaxCertsBehavior::Prompt(revoke_prompt.clone()),
            app_dir,
            udid,
            cbs,
        )
        .await?
    } else {
        let sign_progress = move |f: f32| {
            cbs.progress("Signing…", f64::from(f).clamp(0.0, 1.0));
            std::future::ready(())
        };
        sideloader
            // No pairing file: that's for AltStore's remote-AltServer setup, and AltLoad
            // is AltStore's AltServer itself. The UDID matches the ALTDeviceID we wrote.
            .sign_app(app_dir, Some(team.clone()), false, Some(sign_progress), None, Some(udid))
            .await
            .map_err(|e| err("Signing failed", e))?
            .0
    };
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
