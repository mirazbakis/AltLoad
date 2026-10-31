// Apple ID sign-in with anisette server failover.

use super::*;

use std::sync::Arc;

use isideload::anisette::AnisetteDataGenerator;
use isideload::auth::apple_account::AppToken;
use isideload::auth::grandslam::GrandSlam;
use tokio::sync::RwLock;

/// Signs in to the Apple ID (GSA + anisette, 2FA through the prompt callback)
/// and opens a developer-services session. Shared by installs and the
/// certificate manager.
///
/// `anisette_urls` is one server or several separated by newlines, best first.
/// When Apple or a server rejects the anisette data (a dead server, -45061,
/// -80045 and the like) the next one is tried. Wrong passwords, 2FA problems and
/// cancellations stop right away so the account isn't hammered.
pub(super) async fn sign_in(
    apple_id: &str,
    password: &str,
    anisette_urls: &str,
    cbs: Callbacks,
    replies: Replies,
) -> Result<DeveloperSession, String> {
    let urls: Vec<&str> = anisette_urls
        .split(['\n', ',', ' '])
        .map(str::trim)
        .filter(|u| !u.is_empty())
        .collect();
    let urls = if urls.is_empty() { vec!["https://ani.jkcoxson.com"] } else { urls };

    if let Some(session) = restore_session(apple_id, &urls).await {
        return Ok(session);
    }

    let mut failures: Vec<String> = Vec::new();
    for (i, url) in urls.iter().enumerate() {
        if i > 0 {
            cbs.progress(&format!("Signing in to Apple (trying {})…", host_of(url)), -1.0);
        }
        match sign_in_with(apple_id, password, url, cbs, replies.clone()).await {
            Ok(session) => return Ok(session),
            Err((e, detail)) => {
                let retry = is_anisette_failure(&detail) && i + 1 < urls.len();
                failures.push(format!("{}: {e}", host_of(url)));
                if !retry {
                    break;
                }
            }
        }
    }

    let last = failures.last().cloned().unwrap_or_default();
    if failures.len() > 1 {
        Err(format!(
            "Apple ID sign-in failed with every anisette server AltLoad tried.\n\n{}",
            failures.join("\n")
        ))
    } else {
        Err(last)
    }
}

pub(super) async fn sign_in_with(
    apple_id: &str,
    password: &str,
    anisette_url: &str,
    cbs: Callbacks,
    replies: Replies,
) -> Result<DeveloperSession, (String, String)> {
    let anisette = anisette_provider(anisette_url)
        .map_err(|e| (err("Anisette setup failed", &e), format!("anisette {e:?}")))?;

    let two_factor = move |params: TwoFactorCallbackParams| {
        let replies = replies.clone();
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

    let mut account = AppleAccount::builder(apple_id)
        .anisette_provider(anisette)
        .login(password, two_factor)
        .await
        .map_err(|e| (err("Apple ID sign-in failed", &e), format!("{e} {e:?}")))?;

    let token = account
        .get_app_token("xcode.auth")
        .await
        .map_err(|e| (err("Couldn't open a developer session", &e), format!("{e} {e:?}")))?;
    let adsid = account
        .spd
        .as_ref()
        .and_then(|spd| spd.get("adsid"))
        .and_then(|v| v.as_string())
        .map(str::to_string)
        .ok_or_else(|| ("Couldn't open a developer session: Apple sent no account ID.".to_string(), String::new()))?;

    save_session(apple_id, &token, &adsid, anisette_url);
    Ok(DeveloperSession::new(
        token,
        adsid,
        account.grandslam_client.clone(),
        account.anisette_generator.clone(),
    ))
}

/// Each server provisions its own anisette identity, so each gets its own folder.
fn anisette_provider(anisette_url: &str) -> Result<RemoteV3AnisetteProvider, rootcause::Report> {
    Ok(RemoteV3AnisetteProvider::default()?
        .set_url(anisette_url)
        .set_storage(Box::new(FileStorage::new(
            &format!("anisette/{}", host_of(anisette_url)),
            Some("AltLoad.anisette"),
        ))))
}

// MARK: - Saved session
//
// Signing in is the step anisette servers break most often, and repeating it risks
// 2FA prompts and rate limits. Apple's developer token outlasts the sign-in, so it's
// kept and reused until Apple stops accepting it.

const SESSION_KEY: &str = "xcode";
/// Treat a token this close to expiring as already gone, so it can't run out mid-install.
const SESSION_MARGIN_SECS: u64 = 60 * 60;

fn session_storage() -> FileStorage {
    FileStorage::new("session", None)
}

fn save_session(apple_id: &str, token: &AppToken, adsid: &str, anisette_url: &str) {
    let saved = serde_json::json!({
        "appleID": apple_id.to_lowercase(),
        "token": token.token,
        "duration": token.duration,
        "expiry": token.expiry,
        "adsid": adsid,
        "anisette": anisette_url,
    });
    // Not fatal: the next run just signs in again.
    let _ = session_storage().store(SESSION_KEY, &saved.to_string());
}

/// The saved developer session for this Apple ID, if Apple still accepts it.
async fn restore_session(apple_id: &str, urls: &[&str]) -> Option<DeveloperSession> {
    let storage = session_storage();
    let saved: serde_json::Value = serde_json::from_str(&storage.retrieve(SESSION_KEY).ok()??).ok()?;
    if saved["appleID"].as_str()? != apple_id.to_lowercase() {
        return None;
    }

    let expiry = saved["expiry"].as_u64()?;
    // Apple sends milliseconds.
    let expires_at = if expiry > 100_000_000_000 { expiry / 1000 } else { expiry };
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
    if expires_at <= now + SESSION_MARGIN_SECS {
        let _ = storage.delete(SESSION_KEY);
        return None;
    }

    let token = AppToken {
        token: saved["token"].as_str()?.to_string(),
        duration: saved["duration"].as_u64()?,
        expiry,
    };
    let adsid = saved["adsid"].as_str()?;

    // The server the token came from first, then the others: a dead server shouldn't
    // cost a sign-in while the token is still good.
    let first = saved["anisette"].as_str()?;
    let others = urls.iter().copied().filter(|u| *u != first);
    for url in std::iter::once(first).chain(others) {
        match session_with(token.clone(), adsid, url).await {
            Ok(session) => return Some(session),
            Err(detail) if is_anisette_failure(&detail) => continue,
            Err(_) => {
                // Apple turned the token down, so it's no use to anyone.
                let _ = storage.delete(SESSION_KEY);
                return None;
            }
        }
    }
    None
}

async fn session_with(token: AppToken, adsid: &str, anisette_url: &str) -> Result<DeveloperSession, String> {
    let describe = |e: rootcause::Report| format!("anisette {e} {e:?}");
    let provider = anisette_provider(anisette_url).map_err(describe)?;
    let generator = AnisetteDataGenerator::new(Arc::new(RwLock::new(provider)));
    let client_info = generator.get_client_info().await.map_err(describe)?;
    let client = GrandSlam::new(client_info, false, None).await.map_err(describe)?;

    let mut session = DeveloperSession::new(token, adsid.to_string(), Arc::new(client), generator);
    // The cheapest request that proves the token still works.
    session.list_teams().await.map_err(|e| format!("{e} {e:?}"))?;
    Ok(session)
}

/// Errors that come from the anisette server or Apple refusing its data, where
/// another server may well work. Anything about the password, 2FA or the user
/// cancelling is not retried.
pub(super) fn is_anisette_failure(message: &str) -> bool {
    let m = message.to_lowercase();
    let user_side = ["-22406", "incorrect", "password", "2fa", "two-factor", "verification code", "cancel", "abort", "locked", "disabled"];
    if user_side.iter().any(|s| m.contains(s)) && !m.contains("anisette") {
        return false;
    }
    [
        "anisette", "provision", "client info", "client_info", "-45061", "-45054", "-80045",
        "-22410", "-22411", "websocket", "error sending request", "timed out", "connection",
        "dns", "certificate verify", "status code 5", "502", "503", "504",
    ]
    .iter()
    .any(|s| m.contains(s))
}

pub(super) fn host_of(url: &str) -> String {
    url.trim()
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .split('/')
        .next()
        .unwrap_or("anisette")
        .replace(':', "_")
}
