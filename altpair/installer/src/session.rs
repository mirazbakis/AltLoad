// Runs the core's install session (core/src/install/mod.rs) on a worker thread
// while this thread shows progress and answers its prompts.

use std::ffi::{c_char, c_void, CStr, CString};
use std::ptr;
use std::sync::mpsc::{channel, Sender};

use altload_ffi::{
    altload_install_result_free, altload_install_session_cancel, altload_install_session_free,
    altload_install_session_new, altload_install_session_respond, altload_install_session_run,
    AltLoadEndpoint, AltLoadInstallConfig, AltLoadInstallResult, AltLoadInstallSession,
};

use crate::prompts::{self, Cert};
use crate::term;
use crate::ui::{self, Progress};

/// Everything the core needs for one install. Mirrors what
/// ios/App/Core/Install/InstallController.swift (`runSession`) passes.
pub struct Request {
    pub apple_id: String,
    pub password: String,
    /// Newline-separated anisette servers, best first.
    pub anisette: String,
    pub pairing_file: String,
    pub ipa: String,
    pub server_id: String,
}

pub struct Installed {
    pub app_name: String,
    pub app_version: String,
}

enum Event {
    Progress(String, f64),
    Prompt(i32, String),
    Done(Result<Installed, String>),
}

/// The callbacks' context: where to send what the core reports.
struct Ctx {
    tx: Sender<Event>,
}

extern "C" fn on_progress(ctx: *mut c_void, stage: *const c_char, fraction: f64) {
    let ctx = unsafe { &*(ctx as *const Ctx) };
    let stage = unsafe { text(stage) };
    let _ = ctx.tx.send(Event::Progress(stage, fraction));
}

extern "C" fn on_prompt(ctx: *mut c_void, kind: i32, json: *const c_char) {
    let ctx = unsafe { &*(ctx as *const Ctx) };
    let json = unsafe { text(json) };
    let _ = ctx.tx.send(Event::Prompt(kind, json));
}

unsafe fn text(p: *const c_char) -> String {
    if p.is_null() {
        String::new()
    } else {
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

/// The session pointer, shared with the worker thread. The core allows
/// `respond` and `cancel` from another thread while `run` is blocked.
#[derive(Clone, Copy)]
struct SessionPtr(*mut AltLoadInstallSession);
unsafe impl Send for SessionPtr {}

/// The host LocalDevVPN loops back into this iPhone and remotepairingd's port.
/// Mirrors ios/App/Core/Device/LocalDevVPN.swift (defaultTargetIP, remotePairingPort).
const VPN_TARGET: &str = "10.7.0.1";
const REMOTE_PAIRING_PORT: u16 = 49152;
/// The pairing host's name and the certificate's machine name.
/// Mirrors InstallController.swift (host_name and machine_name "AltLoad").
const HOST_NAME: &str = "AltLoad";
const MACHINE_NAME: &str = "AltLoad";
/// The name this device is registered under on the team. The app uses
/// UIDevice.current.name, which a Linux shell can't read; the core's default is "iPhone".
const DEVICE_NAME: &str = "iPhone";

pub fn run(mut req: Request) -> Result<Installed, String> {
    let session = altload_install_session_new();
    if session.is_null() {
        return Err("Couldn't start an install session.".into());
    }
    let session = SessionPtr(session);
    let (tx, rx) = channel::<Event>();

    let worker = {
        let tx = tx.clone();
        let apple_id = std::mem::take(&mut req.apple_id);
        let password = std::mem::take(&mut req.password);
        let anisette = std::mem::take(&mut req.anisette);
        let pairing = std::mem::take(&mut req.pairing_file);
        let ipa = std::mem::take(&mut req.ipa);
        let server_id = std::mem::take(&mut req.server_id);
        std::thread::Builder::new()
            .name("install".into())
            .spawn(move || {
                let session = session;
                let outcome = run_blocking(session, &tx, apple_id, password, anisette, pairing, ipa, server_id);
                let _ = tx.send(Event::Done(outcome));
            })
            .map_err(|e| format!("Couldn't start the install thread: {e}"))?
    };
    drop(tx);

    let tty = term::is_tty(libc::STDOUT_FILENO);
    let mut progress = Progress::new(tty);
    let mut outcome = Err("The install stopped unexpectedly.".to_string());
    for event in rx {
        match event {
            Event::Progress(stage, fraction) => progress.write(&stage, fraction),
            Event::Prompt(kind, json) => {
                progress.close();
                let mut reply = answer(kind, &json);
                let c = CString::new(reply.as_str()).unwrap_or_default();
                let rc = unsafe { altload_install_session_respond(session.0, c.as_ptr()) };
                term::wipe(&mut reply);
                if rc != 0 {
                    unsafe { altload_install_session_cancel(session.0) };
                }
            }
            Event::Done(result) => {
                outcome = result;
                break;
            }
        }
    }
    progress.close();
    let _ = worker.join();
    unsafe { altload_install_session_free(session.0) };
    outcome
}

#[allow(clippy::too_many_arguments)]
fn run_blocking(
    session: SessionPtr,
    tx: &Sender<Event>,
    apple_id: String,
    mut password: String,
    anisette: String,
    pairing: String,
    ipa: String,
    server_id: String,
) -> Result<Installed, String> {
    let c = |s: &str| CString::new(s).map_err(|_| "A setting contains a NUL byte.".to_string());
    let apple_id = c(&apple_id)?;
    let password_c = c(&password);
    term::wipe(&mut password);
    let password_c = password_c?;
    let anisette = c(&anisette)?;
    let pairing = c(&pairing)?;
    let ipa = c(&ipa)?;
    let server_id = c(&server_id)?;
    let host = c(VPN_TARGET)?;
    let host_name = c(HOST_NAME)?;
    let machine = c(MACHINE_NAME)?;
    let device = c(DEVICE_NAME)?;

    let endpoint = AltLoadEndpoint {
        host: host.as_ptr(),
        port: REMOTE_PAIRING_PORT,
        identifier: ptr::null(),
        auth_tag: ptr::null(),
    };
    let config = AltLoadInstallConfig {
        apple_id: apple_id.as_ptr(),
        password: password_c.as_ptr(),
        anisette_url: anisette.as_ptr(),
        pairing_file_path: pairing.as_ptr(),
        host_name: host_name.as_ptr(),
        endpoints: &endpoint,
        endpoint_count: 1,
        ipa_path: ipa.as_ptr(),
        device_name: device.as_ptr(),
        machine_name: machine.as_ptr(),
        server_id: server_id.as_ptr(),
        // No extra capabilities; extensions kept as they are (mode 0).
        capabilities: ptr::null(),
        extensions_mode: 0,
    };

    let ctx = Box::new(Ctx { tx: tx.clone() });
    let mut out = AltLoadInstallResult {
        error: ptr::null_mut(),
        bundle_id: ptr::null_mut(),
        app_name: ptr::null_mut(),
        app_version: ptr::null_mut(),
        udid: ptr::null_mut(),
        team_id: ptr::null_mut(),
        expiration_unix: 0,
        certificates: ptr::null_mut(),
    };
    let rc = unsafe {
        altload_install_session_run(
            session.0,
            &config,
            Some(on_progress),
            Some(on_prompt),
            &*ctx as *const Ctx as *mut c_void,
            &mut out,
        )
    };

    // Zero the password copy before it is freed.
    let mut secret = password_c.into_bytes();
    secret.fill(0);
    drop(secret);

    let result = if rc == 0 {
        Ok(Installed {
            app_name: unsafe { text(out.app_name) },
            app_version: unsafe { text(out.app_version) },
        })
    } else {
        let message = unsafe { text(out.error) };
        Err(if message.is_empty() { format!("Install failed (code {rc}).") } else { message })
    };
    unsafe { altload_install_result_free(&mut out) };
    drop(ctx);
    result
}

/// Asks the user and returns the reply for `altload_install_session_respond`.
fn answer(kind: i32, json: &str) -> String {
    match kind {
        prompts::TWO_FACTOR => ask_two_factor(json),
        prompts::REVOKE_CERTS => ask_revoke(&prompts::certs_from_json(json)),
        _ => "abort".into(),
    }
}

fn ask_two_factor(json: &str) -> String {
    for note in prompts::two_factor_notes(json) {
        ui::note(&note);
    }
    loop {
        let Ok(Some(line)) = term::read_line("      Two-factor code: ") else {
            return "abort".into();
        };
        let line = line.trim();
        if line.is_empty() {
            return "abort".into();
        }
        match crate::handoff::normalize_code(line) {
            Some(code) => return format!("code:{code}"),
            None => println!("      Enter the 6 digits, or return to stop."),
        }
    }
}

fn ask_revoke(certs: &[Cert]) -> String {
    if certs.is_empty() {
        return "abort".into();
    }
    ui::note("Your team has too many certificates. Choose ones to revoke:");
    for (i, cert) in certs.iter().enumerate() {
        let name = if cert.name.is_empty() { "Certificate" } else { &cert.name };
        let line = if cert.machine.is_empty() {
            format!("      {}. {name}", i + 1)
        } else {
            format!("      {}. {name} ({})", i + 1, cert.machine)
        };
        println!("{}", ui::fit(&line, ui::WIDTH));
    }
    ui::note("Numbers separated by spaces, or return to cancel.");
    loop {
        let Ok(Some(line)) = term::read_line("      Revoke: ") else {
            return "abort".into();
        };
        match prompts::parse_cert_choice(&line, certs.len()) {
            Ok(Some(chosen)) => return prompts::revoke_reply(certs, &chosen),
            Ok(None) => return "abort".into(),
            Err(e) => println!("      {}", ui::fit(&e, ui::WIDTH - 6)),
        }
    }
}
