// The core's prompts (core/src/install/prompts.rs) and the answers it expects
// (altload_install_session_respond in core/src/install/mod.rs).

/// Kind 1: the Apple ID needs a two-factor code. Answer "code:<digits>",
/// "sms:<id>", "devices", "resend" or "abort".
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

/// The two-factor prompt from the core (see isideload's TwoFactorCallbackParams).
#[derive(Debug, Default)]
pub struct TwoFactor {
    /// Apple's last answer, such as a wrong code.
    pub last_error: Option<String>,
    /// The last way of sending a code failed, so a new one must be chosen
    /// before a code can be entered. isideload refuses a code or "resend" here.
    pub unknown: bool,
    /// The code went by text message (to `selected`), not to trusted devices.
    pub sms: bool,
    /// Trusted phone numbers: (id, masked number).
    pub numbers: Vec<(u64, String)>,
    pub selected: Option<u64>,
}

pub fn two_factor_from_json(json: &str) -> TwoFactor {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    TwoFactor {
        last_error: v["lastError"].as_str().filter(|e| !e.is_empty()).map(str::to_string),
        unknown: v["unknown"].as_bool() == Some(true),
        sms: v["sms"].as_bool() == Some(true),
        numbers: v["numbers"]
            .as_array()
            .map(|ns| {
                ns.iter()
                    .filter_map(|n| Some((n["id"].as_u64()?, n["number"].as_str().unwrap_or_default().to_string())))
                    .collect()
            })
            .unwrap_or_default(),
        selected: v["selectedNumberId"].as_u64(),
    }
}

/// What to show above the two-factor question: the last error, where the code
/// went, and what can be typed.
pub fn two_factor_notes(tf: &TwoFactor) -> Vec<String> {
    let mut notes = Vec::new();
    if let Some(e) = &tf.last_error {
        notes.push(e.clone());
    }
    if tf.unknown {
        notes.push("That way of getting a code didn't work. Choose another.".into());
    } else if tf.sms {
        let number = tf
            .numbers
            .iter()
            .find(|(id, _)| Some(*id) == tf.selected)
            .or(tf.numbers.first())
            .map(|(_, n)| n.as_str())
            .filter(|n| !n.is_empty());
        notes.push(match number {
            Some(n) => format!("A code was sent by text to {n}."),
            None => "A code was sent by text message.".to_string(),
        });
    } else {
        notes.push("Enter the code shown on your devices.".into());
    }
    if tf.numbers.len() > 1 {
        for (i, (_, n)) in tf.numbers.iter().enumerate() {
            notes.push(format!("s{}: text {n}", i + 1));
        }
    }
    let mut options = Vec::new();
    if !tf.unknown {
        options.push("the 6 digits");
        options.push("r to resend");
    }
    if tf.unknown || tf.sms {
        options.push("d for your devices");
    }
    if !tf.numbers.is_empty() {
        options.push(if tf.numbers.len() > 1 { "s1, s2… for a text" } else { "s for a text" });
    }
    notes.push(format!("Type {}, or return to stop.", options.join(", ")));
    notes
}

/// Turns what was typed at the two-factor question into the core's reply:
/// "code:<digits>", "resend", "devices", "sms:<id>" or "abort" (empty line).
pub fn two_factor_reply(input: &str, tf: &TwoFactor) -> Result<String, String> {
    let input = input.trim().to_ascii_lowercase();
    if input.is_empty() {
        return Ok("abort".into());
    }
    if let Some(code) = crate::handoff::normalize_code(&input) {
        if tf.unknown {
            return Err("Choose where to get a code first.".into());
        }
        return Ok(format!("code:{code}"));
    }
    match input.as_str() {
        "r" | "resend" if !tf.unknown => return Ok("resend".into()),
        "d" | "devices" => return Ok("devices".into()),
        _ => {}
    }
    if let Some(rest) = input.strip_prefix('s') {
        let rest = rest.trim_start_matches("ms").trim();
        if tf.numbers.is_empty() {
            return Err("No phone number to text.".into());
        }
        let index = if rest.is_empty() {
            tf.numbers
                .iter()
                .position(|(id, _)| Some(*id) == tf.selected)
                .unwrap_or(0)
        } else {
            match rest.parse::<usize>() {
                Ok(n) if (1..=tf.numbers.len()).contains(&n) => n - 1,
                _ => return Err(format!("Pick a number from s1 to s{}.", tf.numbers.len())),
            }
        };
        return Ok(format!("sms:{}", tf.numbers[index].0));
    }
    Err(if tf.unknown {
        "Type d or s to choose.".into()
    } else {
        "Enter the 6 digits.".into()
    })
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
        let notes = two_factor_notes(&two_factor_from_json(json));
        assert_eq!(notes[0], "Incorrect code");
        assert_eq!(notes[1], "A code was sent by text to +44 •••• ••22.");
        assert_eq!(notes[2], "s1: text +1 (•••) •••-••11");
        let notes = two_factor_notes(&two_factor_from_json(r#"{"sms":false,"numbers":[]}"#));
        assert_eq!(notes[0], "Enter the code shown on your devices.");
        assert_eq!(notes[1], "Type the 6 digits, r to resend, or return to stop.");
    }

    #[test]
    fn two_factor_replies() {
        let devices = two_factor_from_json(r#"{"sms":false,"numbers":[{"id":7,"number":"x"},{"id":9,"number":"y"}]}"#);
        assert_eq!(two_factor_reply("123 456", &devices).as_deref(), Ok("code:123456"));
        assert_eq!(two_factor_reply("", &devices).as_deref(), Ok("abort"));
        assert_eq!(two_factor_reply("r", &devices).as_deref(), Ok("resend"));
        assert_eq!(two_factor_reply("s", &devices).as_deref(), Ok("sms:7"));
        assert_eq!(two_factor_reply("S2", &devices).as_deref(), Ok("sms:9"));
        assert_eq!(two_factor_reply("sms 2", &devices).as_deref(), Ok("sms:9"));
        assert!(two_factor_reply("s3", &devices).is_err());
        assert!(two_factor_reply("12345", &devices).is_err());

        // After a failed method a code or resend is refused by isideload, so ask for a method.
        let unknown = two_factor_from_json(r#"{"unknown":true,"sms":false,"numbers":[{"id":4,"number":"x"}]}"#);
        assert!(two_factor_reply("123456", &unknown).is_err());
        assert!(two_factor_reply("r", &unknown).is_err());
        assert_eq!(two_factor_reply("d", &unknown).as_deref(), Ok("devices"));
        assert_eq!(two_factor_reply("s", &unknown).as_deref(), Ok("sms:4"));
        let notes = two_factor_notes(&unknown);
        assert!(notes.last().unwrap().starts_with("Type d for your devices, s for a text"));

        let sms = two_factor_from_json(r#"{"sms":true,"selectedNumberId":9,"numbers":[{"id":7,"number":"x"},{"id":9,"number":"y"}]}"#);
        assert_eq!(two_factor_reply("s", &sms).as_deref(), Ok("sms:9"));
        assert_eq!(two_factor_reply("d", &sms).as_deref(), Ok("devices"));
        let none = two_factor_from_json(r#"{"sms":false,"numbers":[]}"#);
        assert!(two_factor_reply("s", &none).is_err());
    }
}
