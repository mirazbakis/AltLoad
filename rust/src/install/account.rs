// Certificate manager: account requests against the signed-in Apple ID's own team.

use super::*;

/// Runs one account request against the signed-in Apple ID's own team.
///
/// `request_json`:
///   {"op":"overview"}                          list certificates, App IDs, devices
///   {"op":"revoke","serials":["ABC…", …]}      revoke those certificates, then list
///
/// On success returns 0 and `*out_json` holds the overview JSON; on failure
/// returns 1 and `*out_json` holds the error message. Free with
/// `altload_string_free`. Prompts (2FA) and cancellation use the same
/// `AltLoadInstallSession` as installs.
#[no_mangle]
pub unsafe extern "C" fn altload_account_session_run(
    session: *mut AltLoadInstallSession,
    apple_id: *const c_char,
    password: *const c_char,
    anisette_url: *const c_char,
    request_json: *const c_char,
    progress_cb: AltLoadProgressCb,
    prompt_cb: AltLoadPromptCb,
    ctx: *mut c_void,
    out_json: *mut *mut c_char,
) -> i32 {
    if session.is_null() || out_json.is_null() {
        return 2;
    }
    *out_json = ptr::null_mut();
    init_once();

    let fail = |msg: String| -> i32 {
        *out_json = cstr(msg);
        1
    };
    let apple_id = match req(apple_id, "Apple ID") { Ok(v) => v, Err(e) => return fail(e) };
    let password = match req(password, "password") { Ok(v) => v, Err(e) => return fail(e) };
    let anisette = opt(anisette_url, "https://ani.jkcoxson.com");
    let request: serde_json::Value = serde_json::from_str(&opt(request_json, "{}"))
        .unwrap_or_else(|_| serde_json::json!({}));

    let session = &*session;
    let (tx, rx) = mpsc::unbounded_channel();
    *session.responder.lock().unwrap() = Some(tx);
    session.cancelled.store(false, Ordering::SeqCst);
    let cbs = Callbacks { progress: progress_cb, prompt: prompt_cb, ctx };

    let rt = match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(rt) => rt,
        Err(e) => return fail(format!("failed to start runtime: {e}")),
    };
    let result = rt.block_on(run_account(
        apple_id,
        password,
        anisette,
        request,
        cbs,
        Arc::new(AsyncMutex::new(rx)),
        &session.cancelled,
    ));
    *session.responder.lock().unwrap() = None;

    match result {
        Ok(json) => {
            *out_json = cstr(json.to_string());
            0
        }
        Err(e) => fail(e),
    }
}

#[no_mangle]
pub unsafe extern "C" fn altload_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

pub(super) async fn run_account(
    apple_id: String,
    password: String,
    anisette: String,
    request: serde_json::Value,
    cbs: Callbacks,
    replies: Replies,
    cancelled: &AtomicBool,
) -> Result<serde_json::Value, String> {
    let check = || if cancelled.load(Ordering::SeqCst) { Err("Cancelled.".to_string()) } else { Ok(()) };

    cbs.progress("Signing in to Apple…", -1.0);
    let mut dev = sign_in(&apple_id, &password, &anisette, cbs, replies).await?;
    check()?;

    cbs.progress("Loading your account…", -1.0);
    let team = dev
        .list_teams()
        .await
        .map_err(|e| err("Couldn't load your developer team", e))?
        .into_iter()
        .next()
        .ok_or("This Apple ID has no developer team.")?;

    if request.get("op").and_then(|v| v.as_str()) == Some("revoke") {
        let serials: Vec<String> = request
            .get("serials")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().filter_map(|s| s.as_str().map(str::to_string)).collect())
            .unwrap_or_default();
        let total = serials.len().max(1) as f64;
        for (i, serial) in serials.iter().enumerate() {
            check()?;
            cbs.progress("Revoking certificate…", i as f64 / total);
            dev.revoke_development_cert(&team, serial, None::<DeveloperDeviceType>)
                .await
                .map_err(|e| err("Couldn't revoke the certificate", e))?;
        }
    }

    check()?;
    cbs.progress("Loading your account…", -1.0);
    account_overview(&mut dev, &team).await
}

pub(super) fn unix(date: Option<plist::Date>) -> i64 {
    date.and_then(|d| SystemTime::from(d).duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

pub(super) async fn account_overview(
    dev: &mut DeveloperSession,
    team: &DeveloperTeam,
) -> Result<serde_json::Value, String> {
    let certs = dev
        .list_ios_certs(team)
        .await
        .map_err(|e| err("Couldn't list certificates", e))?;

    let certificates: Vec<serde_json::Value> = certs
        .iter()
        .map(|c| {
            serde_json::json!({
                "serial": c.serial_number.clone().unwrap_or_default(),
                "certificateId": c.certificate_id.clone().unwrap_or_default(),
                "name": c.name.clone().unwrap_or_default(),
                "machineName": c.machine_name.clone().unwrap_or_default(),
                "machineId": c.machine_id.clone().unwrap_or_default(),
                "platform": c.certificate_platform.clone().unwrap_or_default(),
                "type": c.certificate_type.as_ref().and_then(|t| t.name.clone()).unwrap_or_default(),
                "maxActive": c.certificate_type.as_ref().and_then(|t| t.max_active_certs).unwrap_or(0),
                "status": c.status.clone().unwrap_or_default(),
                "expires": unix(c.expiration_date.clone()),
            })
        })
        .collect();

    // App IDs and devices are extra detail: don't fail the whole overview if
    // Apple refuses one of them.
    let app_ids = match dev.list_app_ids(team, None::<DeveloperDeviceType>).await {
        Ok(r) => serde_json::json!({
            "items": r.app_ids.iter().map(|a| serde_json::json!({
                "id": a.app_id_id,
                "identifier": a.identifier,
                "name": a.name,
                "expires": unix(a.expiration_date.clone()),
            })).collect::<Vec<_>>(),
            "max": r.max_quantity,
            "available": r.available_quantity,
        }),
        Err(e) => serde_json::json!({ "error": e.to_string() }),
    };

    let devices = match dev.list_devices(team, None::<DeveloperDeviceType>).await {
        Ok(list) => serde_json::Value::Array(
            list.iter()
                .map(|d| serde_json::json!({
                    "name": d.name.clone().unwrap_or_default(),
                    "udid": d.device_number,
                    "status": d.status.clone().unwrap_or_default(),
                }))
                .collect(),
        ),
        Err(_) => serde_json::Value::Array(Vec::new()),
    };

    Ok(serde_json::json!({
        "team": { "id": team.team_id, "name": team.name.clone().unwrap_or_default() },
        "certificates": certificates,
        "appIds": app_ids,
        "devices": devices,
    }))
}
