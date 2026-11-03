// Apple ID sign-in with anisette server failover.

use super::*;

/// Signs in to the Apple ID (GSA + anisette, 2FA through the prompt callback)
/// and opens a developer-services session. Shared by installs and the
/// certificate manager.
///
/// `anisette_urls` is one server or several separated by newlines, best first.
/// When Apple or a server rejects the anisette data (a dead server, -45061,
/// -80045 and the like) one more is tried. So is -22406, which Apple also sends
/// for anisette data it won't accept. 2FA problems and cancellations stop right
/// away so the account isn't hammered.
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

    // v1.3.0 saved the developer token here; it's no longer used, so don't keep it.
    let _ = FileStorage::new("session", None).delete("xcode");

    let urls = &urls[..urls.len().min(MAX_SERVERS_PER_TRY)];
    check_pause(apple_id)?;

    let mut failures: Vec<String> = Vec::new();
    let mut refused = false;
    for (i, url) in urls.iter().enumerate() {
        if i > 0 {
            cbs.progress(&format!("Signing in to Apple (trying {})…", host_of(url)), -1.0);
        }
        match sign_in_with(apple_id, password, url, cbs, replies.clone()).await {
            Ok(session) => {
                clear_pause();
                return Ok(session);
            }
            Err((e, detail)) => match classify_failure(&detail) {
                SignInFailure::PasswordOrAnisette => {
                    refused = true;
                    failures.push(format!("{}: {e}", host_of(url)));
                    if i + 1 == urls.len() {
                        record_rejection(apple_id, false);
                        return Err(PASSWORD_OR_ANISETTE.to_string());
                    }
                }
                SignInFailure::Locked => {
                    record_rejection(apple_id, true);
                    return Err(LOCKED.to_string());
                }
                SignInFailure::RateLimited => {
                    record_rejection(apple_id, true);
                    return Err(RATE_LIMITED.to_string());
                }
                SignInFailure::Anisette if i + 1 < urls.len() => {
                    failures.push(format!("{}: {e}", host_of(url)));
                }
                _ => {
                    failures.push(format!("{}: {e}", host_of(url)));
                    break;
                }
            },
        }
    }

    // One sign-in counts once towards the pause, however many servers it tried.
    if refused {
        record_rejection(apple_id, false);
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
    // Each server provisions its own anisette identity, so each gets its own folder.
    let anisette = RemoteV3AnisetteProvider::default()
        .map_err(|e| (err("Anisette setup failed", &e), format!("anisette {e:?}")))?
        .set_url(anisette_url)
        .set_storage(Box::new(FileStorage::new(
            &format!("anisette/{}", host_of(anisette_url)),
            Some("AltLoad.anisette"),
        )));

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

    DeveloperSession::from_account(&mut account)
        .await
        .map_err(|e| (err("Couldn't open a developer session", &e), format!("{e} {e:?}")))
}

// MARK: - Limits
//
// Apple can lock an account after repeated failed sign-ins, so AltLoad remembers them
// across launches and stops sending the password for a while.

/// Each server is a different device to Apple, so one try only uses a couple.
const MAX_SERVERS_PER_TRY: usize = 2;
/// A typo gets one more try before sign-ins pause.
const REJECTIONS_BEFORE_PAUSE: u64 = 2;
const PAUSE_SECS: u64 = 15 * 60;
const PAUSE_KEY: &str = "pause";

// AppleIDStore.forgetPasswordIfRejected looks for LOCKED's wording. This one
// mustn't match it, since the password may well be right.
const PASSWORD_OR_ANISETTE: &str = "Apple ID sign-in failed: Apple turned down the sign-in with the anisette servers AltLoad tried. Apple answers the same way for a wrong password and for anisette data it won't accept, so check your Apple ID and password, then pick a different server in Settings › Anisette. Too many failed tries can lock your account.";
const LOCKED: &str = "Apple ID sign-in failed: Apple says this Apple ID is locked. Unlock it at iforgot.apple.com, then sign in again.";
const RATE_LIMITED: &str = "Apple ID sign-in failed: Apple is receiving too many requests from this account. Try again later.";

fn pause_storage() -> FileStorage {
    FileStorage::new("signin", None)
}

fn now_secs() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs())
}

fn saved_pause(apple_id: &str) -> Option<serde_json::Value> {
    let saved: serde_json::Value = serde_json::from_str(&pause_storage().retrieve(PAUSE_KEY).ok()??).ok()?;
    (saved["appleID"].as_str()? == apple_id.to_lowercase()).then_some(saved)
}

fn check_pause(apple_id: &str) -> Result<(), String> {
    let until = saved_pause(apple_id).and_then(|saved| saved["until"].as_u64()).unwrap_or(0);
    let now = now_secs();
    if until > now {
        let minutes = (until - now).div_ceil(60);
        return Err(format!(
            "Apple ID sign-in failed: AltLoad paused sign-ins for this Apple ID to help keep it from being locked. Try again in {minutes} min."
        ));
    }
    Ok(())
}

fn record_rejection(apple_id: &str, pause_now: bool) {
    let rejections = saved_pause(apple_id).and_then(|saved| saved["rejections"].as_u64()).unwrap_or(0) + 1;
    let until = if pause_now || rejections >= REJECTIONS_BEFORE_PAUSE { now_secs() + PAUSE_SECS } else { 0 };
    let saved = serde_json::json!({
        "appleID": apple_id.to_lowercase(),
        "rejections": rejections,
        "until": until,
    });
    let _ = pause_storage().store(PAUSE_KEY, &saved.to_string());
}

fn clear_pause() {
    let _ = pause_storage().delete(PAUSE_KEY);
}

#[derive(Debug, PartialEq)]
enum SignInFailure {
    /// -22406 and -20101: a wrong password, or Apple refusing the anisette data.
    PasswordOrAnisette,
    Locked,
    RateLimited,
    /// The anisette server or Apple refusing its data, where another server may well work.
    Anisette,
    Other,
}

/// Apple's error code decides when there is one, since the rest of the report can
/// mention anything. Without a code, anything about the password, 2FA or the user
/// cancelling is not retried.
fn classify_failure(message: &str) -> SignInFailure {
    let m = message.to_lowercase();
    if m.contains("too many requests") {
        return SignInFailure::RateLimited;
    }
    if let Some(code) = auth_error_code(&m) {
        return match code {
            -22406 | -20101 => SignInFailure::PasswordOrAnisette,
            -20209 => SignInFailure::Locked,
            -45061 | -45054 | -80045 | -22410 | -22411 => SignInFailure::Anisette,
            _ if m.contains("locked") || m.contains("disabled") => SignInFailure::Locked,
            _ if m.contains("incorrect") => SignInFailure::PasswordOrAnisette,
            _ => SignInFailure::Other,
        };
    }
    let user_side = ["incorrect", "password", "2fa", "two-factor", "verification code", "cancel", "abort", "locked", "disabled"];
    if user_side.iter().any(|s| m.contains(s)) {
        return SignInFailure::Other;
    }
    let anisette = [
        "anisette", "provision", "client info", "client_info", "websocket", "error sending request",
        "timed out", "connection", "dns", "certificate verify", "status code 5", "502", "503", "504",
    ];
    if anisette.iter().any(|s| m.contains(s)) { SignInFailure::Anisette } else { SignInFailure::Other }
}

fn auth_error_code(lowercased: &str) -> Option<i64> {
    let rest = lowercased.split("auth error ").nth(1)?;
    rest.split(':').next()?.trim().parse().ok()
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_codes_decide_over_the_rest_of_the_report() {
        let wrong = "Auth error -22406: Your Apple ID or password was incorrect. src/anisette/remote_v3.rs connection";
        assert_eq!(classify_failure(wrong), SignInFailure::PasswordOrAnisette);
        assert_eq!(classify_failure("Auth error -20209: This Apple ID has been locked"), SignInFailure::Locked);
        assert_eq!(classify_failure("Auth error -80045: password anisette"), SignInFailure::Anisette);
        assert_eq!(classify_failure("Auth error -99999: Something else"), SignInFailure::Other);
    }

    #[test]
    fn a_refused_sign_in_keeps_the_saved_password() {
        // AppleIDStore deletes the saved password on this wording; -22406 alone can't prove it's wrong.
        assert!(!PASSWORD_OR_ANISETTE.contains("Apple ID or password is incorrect"));
        assert!(LOCKED.contains("Apple ID is locked"));
    }

    #[test]
    fn without_a_code_only_server_problems_move_on() {
        assert_eq!(classify_failure("Failed to get anisette data for login"), SignInFailure::Anisette);
        assert_eq!(classify_failure("Failed to get anisette data for 2FA"), SignInFailure::Other);
        assert_eq!(classify_failure("No 2FA code provided, aborting"), SignInFailure::Other);
        assert_eq!(classify_failure("Received 429 Too Many Requests, no retries left"), SignInFailure::RateLimited);
    }
}
