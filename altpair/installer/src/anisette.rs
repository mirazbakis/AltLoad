// Picking anisette servers for sign-in.
//
// Mirrors ios/App/Core/Account/AnisetteServers.swift: the same built-in list in
// the same order, the same /v3/client_info health check (5 s), and the same
// signInList rules: up to 8 candidates, the ones that answer in order, a
// server the user pinned always first, the first 3 when none answer, at most 4.
// The core then moves on to the next one when a server's data is refused.
//
// The app also appends servers from a live community list, but those go after
// the built-in ones, so the first 8 candidates are the built-in ones either way.

use std::time::Duration;

pub const BUILT_IN: [&str; 10] = [
    "https://ani.jkcoxson.com",
    "https://mac-ani.jkcoxson.com",
    "https://win.ani.sidestore.io",
    "https://ani.sidestore.io",
    "https://ani.sidestore.app",
    "https://ani.sidestore.zip",
    "https://ani.846969.xyz",
    "https://ani.npeg.us",
    "https://anisette.wedotstud.io",
    "https://anisette.crystall1ne.dev",
];

const MAX_CANDIDATES: usize = 8;
const FALLBACK_COUNT: usize = 3;
const MAX_PICKED: usize = 4;

/// The servers to health-check, best first, with a pinned one moved to the front.
pub fn candidates(pinned: Option<&str>) -> Vec<String> {
    let mut order: Vec<String> = BUILT_IN.iter().map(|s| s.to_string()).collect();
    if let Some(p) = pinned.map(normalize).filter(|p| !p.is_empty()) {
        let p = p.as_str();
        order.retain(|a| a != p);
        order.insert(0, p.to_string());
    }
    order.truncate(MAX_CANDIDATES);
    order
}

/// Chooses from the candidates given which ones answered (`alive[i]` for `candidates[i]`).
/// "https://Ani.Example/" and "https://ani.example" are the same server.
fn normalize(url: &str) -> String {
    let url = url.trim().trim_end_matches('/');
    match url.split_once("://") {
        Some((scheme, rest)) => {
            let (host, path) = rest.split_once('/').map_or((rest, ""), |(h, p)| (h, p));
            let path = if path.is_empty() { String::new() } else { format!("/{path}") };
            format!("{}://{}{path}", scheme.to_ascii_lowercase(), host.to_ascii_lowercase())
        }
        None => url.to_string(),
    }
}

pub fn pick(candidates: &[String], alive: &[bool], pinned: Option<&str>) -> Vec<String> {
    let mut picked: Vec<String> = candidates
        .iter()
        .zip(alive)
        .filter(|(_, ok)| **ok)
        .map(|(a, _)| a.clone())
        .collect();
    if let Some(p) = pinned.map(normalize).filter(|p| !p.is_empty()) {
        if !picked.iter().any(|a| *a == p) {
            picked.insert(0, p);
        }
    }
    if picked.is_empty() {
        picked = candidates.iter().take(FALLBACK_COUNT).cloned().collect();
    }
    picked.truncate(MAX_PICKED);
    picked
}

async fn is_alive(client: reqwest::Client, address: String) -> bool {
    let url = format!("{}/v3/client_info", address.trim().trim_end_matches('/'));
    let Ok(resp) = client.get(url).timeout(Duration::from_secs(5)).send().await else {
        return false;
    };
    if resp.status() != reqwest::StatusCode::OK {
        return false;
    }
    let Ok(body) = resp.bytes().await else { return false };
    serde_json::from_slice::<serde_json::Value>(&body)
        .map(|v| v["client_info"].is_string())
        .unwrap_or(false)
}

/// Checks the candidates in parallel and returns the list the core takes:
/// server URLs separated by newlines, best first.
pub async fn sign_in_list(client: &reqwest::Client, pinned: Option<&str>) -> String {
    let candidates = candidates(pinned);
    let checks: Vec<_> = candidates
        .iter()
        .map(|a| tokio::spawn(is_alive(client.clone(), a.clone())))
        .collect();
    let mut alive = Vec::with_capacity(checks.len());
    for check in checks {
        alive.push(check.await.unwrap_or(false));
    }
    pick(&candidates, &alive, pinned).join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn automatic_takes_the_live_ones_in_order() {
        let c = candidates(None);
        assert_eq!(c.len(), 8);
        assert_eq!(c[0], BUILT_IN[0]);
        let alive = [false, true, false, true, true, true, true, false];
        assert_eq!(pick(&c, &alive, None), vec![c[1].clone(), c[3].clone(), c[4].clone(), c[5].clone()]);
    }

    #[test]
    fn none_alive_falls_back_to_the_first_three() {
        let c = candidates(None);
        assert_eq!(pick(&c, &[false; 8], None), c[..3].to_vec());
    }

    #[test]
    fn a_pinned_server_always_goes_first() {
        let pinned = "https://my.ani.example";
        let c = candidates(Some(pinned));
        assert_eq!(c[0], pinned);
        assert_eq!(c.len(), 8);
        let mut alive = [false; 8];
        alive[2] = true;
        assert_eq!(pick(&c, &alive, Some(pinned)), vec![pinned.to_string(), c[2].clone()]);
        // A built-in one pinned moves to the front instead of appearing twice.
        let c = candidates(Some(BUILT_IN[5]));
        assert_eq!(c[0], BUILT_IN[5]);
        assert_eq!(c.iter().filter(|a| *a == BUILT_IN[5]).count(), 1);
        // A trailing slash or capitals don't make a built-in one appear twice.
        let typed = "https://ANI.sidestore.io/";
        let c = candidates(Some(typed));
        assert_eq!(c[0], "https://ani.sidestore.io");
        assert_eq!(c.iter().filter(|a| *a == "https://ani.sidestore.io").count(), 1);
        let mut alive = [false; 8];
        alive[0] = true;
        assert_eq!(pick(&c, &alive, Some(typed)), vec!["https://ani.sidestore.io".to_string()]);
    }
}
