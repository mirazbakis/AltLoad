// JIT sessions: an app launched (or found) and held by debugserver, driven one
// packet at a time from Swift, where a JavaScript script decides what to send.
//
// Being attached once is enough for most apps: the process counts as debugged and
// may map executable memory. On devices where iOS checks each executable page,
// that isn't enough, so emulators stop on `brk` instructions and ask the attached
// debugger to prepare memory for them. Which requests an app makes, and what to
// do about them, lives in the script (AltLoad's own, one the user imported, or
// one the app sends). This file gives the script what it needs:
//
//   altload_debug_open      tunnel, Developer Disk Image, launch suspended (or a
//                           running pid), and a debugserver connection
//   altload_debug_send      one GDB remote packet and its reply
//   altload_debug_continue  resumes the app with a time limit; when nothing stops
//                           it in time, it is interrupted so the script can detach
//   altload_debug_prepare   makes a region usable for JIT by writing one byte
//                           into each 16 KiB page, batched
//   altload_debug_stop      ends any call in progress (from another thread)
//   altload_debug_close     detaches if still attached, and closes the tunnel

use std::ffi::{c_char, c_void, CStr};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use idevice::debug_proxy::{DebugProxyClient, DebugserverCommand};
use idevice::dvt::remote_server::RemoteServerClient;
use idevice::rsd::RsdHandshake;
use idevice::tcp::handle::AdapterHandle;
use idevice::{ReadWrite, RsdService};
use tokio::sync::watch;

use super::device::{device_target, ensure_ddi, launch_suspended};
use super::{cstr, err, init_once, open_tunnel_to, opt, AltLoadInstallConfig, AltLoadProgressCb, Callbacks};

const PAGE: u64 = 16_384;
/// Packets sent before their replies are read, so a large region isn't one round
/// trip per page.
const BATCH: usize = 128;
/// A region larger than this is refused rather than written page by page.
const MAX_REGION: u64 = 16 << 30;
/// How long to wait for the stop an interrupt causes.
const INTERRUPT_WAIT: Duration = Duration::from_secs(5);

type Client = DebugProxyClient<Box<dyn ReadWrite>>;

struct Inner {
    debug: Client,
    // Dropped after `debug`: the launch and the tunnel stay open for the session.
    _launch: Option<RemoteServerClient<Box<dyn ReadWrite>>>,
    _handshake: RsdHandshake,
    _adapter: AdapterHandle,
}

/// One JIT session. Opaque to Swift.
pub struct AltLoadDebugSession {
    rt: tokio::runtime::Runtime,
    inner: Mutex<Option<Inner>>,
    stopped: AtomicBool,
    stop_tx: watch::Sender<bool>,
    pid: u64,
}

impl AltLoadDebugSession {
    /// Runs `f` on the session's connection, ending early when the session is stopped.
    fn with<T>(
        &self,
        f: impl for<'a> FnOnce(&'a mut Client) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<T, String>> + 'a>>,
    ) -> Result<T, String> {
        if self.stopped.load(Ordering::SeqCst) {
            return Err("The JIT session was stopped.".into());
        }
        let mut guard = self.inner.lock().map_err(|_| "The JIT session is broken.".to_string())?;
        let inner = guard.as_mut().ok_or("The JIT session is closed.")?;
        let mut stop = self.stop_tx.subscribe();
        self.rt.block_on(async {
            tokio::select! {
                r = f(&mut inner.debug) => r,
                _ = stop.wait_for(|v| *v) => Err("The JIT session was stopped.".into()),
            }
        })
    }
}

fn packet(data: &str) -> Vec<u8> {
    let sum = data.bytes().fold(0u8, |acc, b| acc.wrapping_add(b));
    format!("${data}#{sum:02x}").into_bytes()
}

fn pages(len: u64) -> u64 {
    if len == 0 { 0 } else { (len - 1) / PAGE + 1 }
}

async fn send(debug: &mut Client, text: &str) -> Result<String, String> {
    let reply = debug
        .send_command(DebugserverCommand::new(text.to_string(), Vec::new()))
        .await
        .map_err(|e| err("debugserver didn't answer", e))?
        .unwrap_or_default();
    // Replies come without acknowledgements from now on.
    if text == "QStartNoAckMode" && reply == "OK" {
        debug.set_ack_mode(false);
    }
    Ok(reply)
}

/// Writes one byte into every page of the region, in batches.
async fn prepare(debug: &mut Client, address: u64, len: u64) -> Result<(), String> {
    if len > MAX_REGION {
        return Err(format!("The app asked for a {len}-byte JIT region, which is more than AltLoad prepares."));
    }
    let count = pages(len);
    let mut next = 0u64;
    while next < count {
        let batch = (count - next).min(BATCH as u64);
        let mut bytes = Vec::with_capacity(batch as usize * 24);
        for i in 0..batch {
            bytes.extend_from_slice(&packet(&format!("M{:x},1:69", address + (next + i) * PAGE)));
        }
        debug.send_raw(&bytes).await.map_err(|e| err("Couldn't write to the app's JIT region", e))?;
        for _ in 0..batch {
            let reply = debug
                .read_response()
                .await
                .map_err(|e| err("Couldn't write to the app's JIT region", e))?
                .unwrap_or_default();
            if reply.starts_with('E') {
                return Err(format!("debugserver couldn't write to the app's JIT region ({reply})."));
            }
        }
        next += batch;
    }
    Ok(())
}

/// Resumes the app with `resume` ("c", or "vCont;S0b:1a2b" to hand back a signal)
/// and waits for it to stop, for at most `limit`. On time out the app is
/// interrupted and an empty reply returned, so the caller knows it went quiet.
async fn continue_for(debug: &mut Client, resume: &str, limit: Duration) -> Result<String, String> {
    // Waiting can then end between packets without leaving an acknowledgement unread.
    if !debug.noack_mode {
        send(debug, "QStartNoAckMode").await?;
    }
    debug.send_raw(&packet(resume)).await.map_err(|e| err("Couldn't let the app run", e))?;
    match tokio::time::timeout(limit, debug.read_response()).await {
        Ok(reply) => Ok(reply.map_err(|e| err("Lost the debugger connection", e))?.unwrap_or_default()),
        Err(_) => {
            debug.send_raw(&[0x03]).await.map_err(|e| err("Couldn't pause the app", e))?;
            let _ = tokio::time::timeout(INTERRUPT_WAIT, debug.read_response()).await;
            Ok(String::new())
        }
    }
}

unsafe fn text(p: *const c_char) -> String {
    if p.is_null() { String::new() } else { CStr::from_ptr(p).to_string_lossy().into_owned() }
}

/// Opens a session. `request_json`: {"ddiDir":"/…/DDI", "bundleId":"com.x"} to
/// launch the app suspended, or {"ddiDir":…, "pid":n} for one already running.
/// Returns 0 with the session in `*out_session` and {"pid":n} in `*out_json`, or 1
/// with an error message in `*out_json`. Free the JSON with `altload_string_free`.
#[no_mangle]
pub unsafe extern "C" fn altload_debug_open(
    config: *const AltLoadInstallConfig,
    request_json: *const c_char,
    progress_cb: AltLoadProgressCb,
    ctx: *mut c_void,
    out_session: *mut *mut AltLoadDebugSession,
    out_json: *mut *mut c_char,
) -> i32 {
    if config.is_null() || out_session.is_null() || out_json.is_null() {
        return 2;
    }
    *out_session = ptr::null_mut();
    *out_json = ptr::null_mut();
    init_once();
    let fail = |msg: String| -> i32 {
        *out_json = cstr(msg);
        1
    };

    let (pairing, host_name, endpoints) = match device_target(&*config) {
        Ok(v) => v,
        Err(e) => return fail(e),
    };
    let request: serde_json::Value = match serde_json::from_str(&opt(request_json, "{}")) {
        Ok(v) => v,
        Err(e) => return fail(err("Bad request", e)),
    };
    let ddi_dir = request.get("ddiDir").and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let bundle_id = request.get("bundleId").and_then(|v| v.as_str()).unwrap_or_default().to_string();
    let pid = request.get("pid").and_then(|v| v.as_u64()).filter(|p| *p > 0);
    if bundle_id.is_empty() && pid.is_none() {
        return fail("Name an app or a process for the JIT session.".into());
    }

    let cbs = Callbacks { progress: progress_cb, prompt: None, ctx };
    let rt = match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(rt) => rt,
        Err(e) => return fail(format!("failed to start runtime: {e}")),
    };
    let opened = rt.block_on(async {
        cbs.progress("Opening device link…", -1.0);
        let (mut adapter, mut handshake) = open_tunnel_to(&pairing, &host_name, &endpoints).await?;
        if !ddi_dir.is_empty() {
            ensure_ddi(&mut adapter, &mut handshake, &ddi_dir, cbs).await?;
        }
        let (pid, launch) = match pid {
            Some(pid) => (pid, None),
            None => {
                let (pid, server) = launch_suspended(&mut adapter, &mut handshake, &bundle_id, cbs).await?;
                (pid, Some(server))
            }
        };
        cbs.progress("Attaching the debugger…", -1.0);
        let debug = DebugProxyClient::connect_rsd(&mut adapter, &mut handshake)
            .await
            .map_err(|e| err("Couldn't open debugserver", e))?;
        Ok::<_, String>((pid, Inner { debug, _launch: launch, _handshake: handshake, _adapter: adapter }))
    });
    match opened {
        Ok((pid, inner)) => {
            let (stop_tx, _) = watch::channel(false);
            let session = AltLoadDebugSession {
                rt,
                inner: Mutex::new(Some(inner)),
                stopped: AtomicBool::new(false),
                stop_tx,
                pid,
            };
            *out_session = Box::into_raw(Box::new(session));
            *out_json = cstr(serde_json::json!({ "pid": pid }).to_string());
            0
        }
        Err(e) => fail(e),
    }
}

/// The process the session is attached to (or launched).
#[no_mangle]
pub unsafe extern "C" fn altload_debug_pid(session: *const AltLoadDebugSession) -> u64 {
    if session.is_null() { 0 } else { (*session).pid }
}

/// Sends one packet (for example "vAttach;1a2b", "c", "m1000,4", "D") and waits
/// for its reply. Returns 0 with the reply (possibly empty) in `*out_reply`, or 1
/// with an error. Free with `altload_string_free`.
#[no_mangle]
pub unsafe extern "C" fn altload_debug_send(
    session: *const AltLoadDebugSession,
    command: *const c_char,
    out_reply: *mut *mut c_char,
) -> i32 {
    if session.is_null() || out_reply.is_null() {
        return 2;
    }
    let command = text(command);
    match (*session).with(move |debug| Box::pin(async move { send(debug, &command).await })) {
        Ok(reply) => { *out_reply = cstr(reply); 0 }
        Err(e) => { *out_reply = cstr(e); 1 }
    }
}

/// Resumes the app with `resume` (NULL or "" for "c") until it stops or
/// `timeout_ms` passes. Returns 0 with the stop reply, or with an empty reply
/// when it timed out (the app is then paused).
#[no_mangle]
pub unsafe extern "C" fn altload_debug_continue(
    session: *const AltLoadDebugSession,
    resume: *const c_char,
    timeout_ms: u64,
    out_reply: *mut *mut c_char,
) -> i32 {
    if session.is_null() || out_reply.is_null() {
        return 2;
    }
    let limit = Duration::from_millis(timeout_ms.max(1));
    let resume = match text(resume) {
        r if r.is_empty() => "c".to_string(),
        r => r,
    };
    match (*session).with(move |debug| Box::pin(async move { continue_for(debug, &resume, limit).await })) {
        Ok(reply) => { *out_reply = cstr(reply); 0 }
        Err(e) => { *out_reply = cstr(e); 1 }
    }
}

/// Makes [address, address + length) usable for JIT. Returns 0 with "OK", or 1
/// with an error.
#[no_mangle]
pub unsafe extern "C" fn altload_debug_prepare(
    session: *const AltLoadDebugSession,
    address: u64,
    length: u64,
    out_reply: *mut *mut c_char,
) -> i32 {
    if session.is_null() || out_reply.is_null() {
        return 2;
    }
    match (*session).with(|debug| Box::pin(async move { prepare(debug, address, length).await.map(|_| "OK".to_string()) })) {
        Ok(reply) => { *out_reply = cstr(reply); 0 }
        Err(e) => { *out_reply = cstr(e); 1 }
    }
}

/// Ends the call in progress and every later one. Safe from any thread.
#[no_mangle]
pub unsafe extern "C" fn altload_debug_stop(session: *const AltLoadDebugSession) {
    if session.is_null() {
        return;
    }
    let s = &*session;
    s.stopped.store(true, Ordering::SeqCst);
    let _ = s.stop_tx.send(true);
}

/// Detaches if the app is still held, then closes the session and frees it.
#[no_mangle]
pub unsafe extern "C" fn altload_debug_close(session: *mut AltLoadDebugSession) {
    if session.is_null() {
        return;
    }
    let session = Box::from_raw(session);
    let inner = session.inner.lock().ok().and_then(|mut g| g.take());
    if let Some(mut inner) = inner {
        session.rt.block_on(async {
            // An app left running needs pausing first; one already detached just
            // answers with an error, which is fine.
            let _ = inner.debug.send_raw(&[0x03]).await;
            let _ = tokio::time::timeout(Duration::from_secs(2), inner.debug.read_response()).await;
            let _ = inner.debug.send_raw(&packet("D")).await;
            let _ = tokio::time::timeout(Duration::from_secs(2), inner.debug.read_response()).await;
        });
        let _guard = session.rt.enter();
        drop(inner);
    }
    let AltLoadDebugSession { rt, .. } = *session;
    rt.shutdown_timeout(Duration::from_secs(1));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packets_carry_their_checksum() {
        assert_eq!(packet("c"), b"$c#63");
        assert_eq!(packet("D"), b"$D#44");
        assert_eq!(packet("M4000,1:69"), b"$M4000,1:69#17");
    }

    #[test]
    fn a_region_is_counted_in_whole_pages() {
        assert_eq!(pages(0), 0);
        assert_eq!(pages(1), 1);
        assert_eq!(pages(PAGE), 1);
        assert_eq!(pages(PAGE + 1), 2);
    }
}
