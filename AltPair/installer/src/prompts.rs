// The core's prompts (core/src/install/prompts.rs) and the answers it expects
// (altload_install_session_respond in core/src/install/mod.rs).

/// Kind 1: the Apple ID needs a two-factor code. Answer "code:<digits>" or "abort".
pub const TWO_FACTOR: i32 = 1;
/// Kind 2: the team has too many certificates. Answer a JSON array of serials, or "abort".
pub const REVOKE_CERTS: i32 = 2;

pub struct Cert {
    pub serial: String,
    pub name: String,
    pub machine: String,
}

/// Reads the certificate list: `[{"serial","name","machine"}, …]`.
pub fn certs_from_json(json: &str) -> Vec<Cert> {
    let Ok(serde_json::Value::Array(items)) = serde_json::from_str(json) else {
        return Vec::new();
    };
    items
        .iter()
        .map(|c| Cert {
            serial: c["serial"].as_str().unwrap_or_default().to_string(),
            name: c["name"].as_str().unwrap_or_default().to_string(),
            machine: c["machine"].as_str().unwrap_or_default().to_string(),
        })
        .collect()
}

/// The reply for the chosen certificates (1-based indexes into `certs`).
pub fn revoke_reply(certs: &[Cert], chosen: &[usize]) -> String {
    let serials: Vec<&str> = chosen.iter().map(|&i| certs[i - 1].serial.as_str()).collect();
    serde_json::to_string(&serials).unwrap_or_else(|_| "abort".into())
}

/// Parses "1 3" (spaces or commas) into 1-based indexes in `1..=count`, in the
/// order typed, without repeats. An empty line means cancel (Ok(None)).
pub fn parse_cert_choice(input: &str, count: usize) -> Result<Option<Vec<usize>>, String> {
    let mut chosen = Vec::new();
    for part in input.split(|c: char| c.is_whitespace() || c == ',').filter(|p| !p.is_empty()) {
        let n: usize = part
            .parse()
            .map_err(|_| format!("\"{part}\" is not a number"))?;
        if n == 0 || n > count {
            return Err(format!("{n} is not in the list (1-{count})"));
        }
        if !chosen.contains(&n) {
            chosen.push(n);
        }
    }
    Ok(if chosen.is_empty() { None } else { Some(chosen) })
}

/// What to show above the two-factor question: the last error and where the code went.
pub fn two_factor_notes(json: &str) -> Vec<String> {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    let mut notes = Vec::new();
    if let Some(e) = v["lastError"].as_str().filter(|e| !e.is_empty()) {
        notes.push(e.to_string());
    }
    if v["sms"].as_bool() == Some(true) {
        let number = v["numbers"]
            .as_array()
            .and_then(|ns| {
                let sel = v["selectedNumberId"].as_u64();
                ns.iter().find(|n| sel.is_some() && n["id"].as_u64() == sel).or(ns.first())
            })
            .and_then(|n| n["number"].as_str());
        notes.push(match number {
            Some(n) => format!("A code was sent by text to {n}."),
            None => "A code was sent by text message.".to_string(),
        });
    } else {
        notes.push("Enter the code shown on your devices.".into());
    }
    notes
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cert_choices() {
        assert_eq!(parse_cert_choice("", 3), Ok(None));
        assert_eq!(parse_cert_choice("   ", 3), Ok(None));
        assert_eq!(parse_cert_choice("1", 3), Ok(Some(vec![1])));
        assert_eq!(parse_cert_choice("3 1", 3), Ok(Some(vec![3, 1])));
        assert_eq!(parse_cert_choice("1,2 2", 3), Ok(Some(vec![1, 2])));
        assert!(parse_cert_choice("0", 3).is_err());
        assert!(parse_cert_choice("4", 3).is_err());
        assert!(parse_cert_choice("1 x", 3).is_err());
        assert!(parse_cert_choice("-1", 3).is_err());
    }

    #[test]
    fn cert_json_round_trip() {
        let json = r#"[{"serial":"AA","name":"iPhone Developer","machine":"AltLoad"},{"serial":"BB","name":"n","machine":"m"}]"#;
        let certs = certs_from_json(json);
        assert_eq!(certs.len(), 2);
        assert_eq!(certs[1].machine, "m");
        assert_eq!(revoke_reply(&certs, &[2, 1]), r#"["BB","AA"]"#);
        assert!(certs_from_json("nope").is_empty());
    }

    #[test]
    fn two_factor_text() {
        let json = r#"{"unknown":false,"sms":true,"lastError":"Incorrect code","selectedNumberId":2,"numbers":[{"id":1,"number":"+1 (•••) •••-••11"},{"id":2,"number":"+44 •••• ••22"}]}"#;
        assert_eq!(two_factor_notes(json), vec!["Incorrect code", "A code was sent by text to +44 •••• ••22."]);
        assert_eq!(two_factor_notes(r#"{"sms":false}"#), vec!["Enter the code shown on your devices."]);
    }
}
