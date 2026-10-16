// Apple ID sign-in with anisette server failover.

use super::*;

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
