// Developer teams: reading the core's list, choosing one, and remembering the choice.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Team {
    pub id: String,
    pub name: String,
    /// "free", "individual", "organization" or "unknown", from the core.
    pub kind: String,
}

impl Team {
    /// "Name (ABCDE12345, free)".
    pub fn label(&self) -> String {
        let name = if self.name.is_empty() { "Team" } else { &self.name };
        format!("{name} ({}, {})", self.id, kind_text(&self.kind))
    }
}

pub fn kind_text(kind: &str) -> &'static str {
    match kind {
        "free" => "free",
        "individual" => "individual",
        "organization" => "organization",
        _ => "unknown type",
    }
}

fn from_value(v: &serde_json::Value) -> Option<Team> {
    let s = |k: &str| v[k].as_str().unwrap_or_default().to_string();
    let id = s("id");
    (!id.is_empty()).then(|| Team { id, name: s("name"), kind: s("kind") })
}

/// Every team in the account overview JSON.
pub fn from_overview(json: &str) -> Vec<Team> {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    v["teams"].as_array().map(|a| a.iter().filter_map(from_value).collect()).unwrap_or_default()
}

/// The team the core reports it used, from `altload_install_session_details`,
/// with its note when it fell back to the first team.
pub fn from_details(json: &str) -> Option<(Team, Option<String>)> {
    let v: serde_json::Value = serde_json::from_str(json).ok()?;
    let team = from_value(&v["team"])?;
    let note = v["teamNote"].as_str().filter(|n| !n.is_empty()).map(str::to_string);
    Some((team, note))
}

/// Reads a choice: empty is the first team, a number is a place in the list,
/// anything else must be a team ID. Returns an index into `teams`.
pub fn parse_choice(input: &str, teams: &[Team]) -> Result<usize, String> {
    let input = input.trim();
    if input.is_empty() {
        return Ok(0);
    }
    if let Ok(n) = input.parse::<usize>() {
        return if (1..=teams.len()).contains(&n) {
            Ok(n - 1)
        } else {
            Err(format!("{n} is not in the list (1-{})", teams.len()))
        };
    }
    teams
        .iter()
        .position(|t| t.id.eq_ignore_ascii_case(input))
        .ok_or_else(|| format!("\"{input}\" is not a team number or ID"))
}

/// The saved choice is "<team id>\t<apple id>", so it is only used for the same Apple ID.
pub fn saved_text(team_id: &str, apple_id: &str) -> String {
    format!("{team_id}\t{}\n", apple_id.to_lowercase())
}

pub fn parse_saved(text: &str, apple_id: &str) -> Option<String> {
    let (team, who) = text.trim().split_once('\t')?;
    (!team.is_empty() && who == apple_id.to_lowercase()).then(|| team.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn two() -> Vec<Team> {
        vec![
            Team { id: "AAAAAAAAAA".into(), name: "Jo Doe".into(), kind: "free".into() },
            Team { id: "BBBBBBBBBB".into(), name: "Studio".into(), kind: "organization".into() },
        ]
    }

    #[test]
    fn reads_the_overview() {
        let json = r#"{"team":{"id":"AAAAAAAAAA"},"teams":[
            {"id":"AAAAAAAAAA","name":"Jo Doe","type":"Individual","kind":"free"},
            {"id":"BBBBBBBBBB","name":"Studio","type":"Company/Organization","kind":"organization"},
            {"name":"no id"}]}"#;
        assert_eq!(from_overview(json), two());
        assert!(from_overview("nonsense").is_empty());
        assert_eq!(two()[0].label(), "Jo Doe (AAAAAAAAAA, free)");
    }

    #[test]
    fn reads_the_details() {
        let json = r#"{"team":{"id":"X1","name":"N","kind":"individual"},"teamNote":"fell back"}"#;
        let (team, note) = from_details(json).unwrap();
        assert_eq!(team.id, "X1");
        assert_eq!(note.as_deref(), Some("fell back"));
        assert!(from_details("{}").is_none());
        assert!(from_details("").is_none());
    }

    #[test]
    fn choices() {
        let t = two();
        assert_eq!(parse_choice("", &t), Ok(0));
        assert_eq!(parse_choice(" 2 ", &t), Ok(1));
        assert_eq!(parse_choice("bbbbbbbbbb", &t), Ok(1));
        assert!(parse_choice("0", &t).is_err());
        assert!(parse_choice("3", &t).is_err());
        assert!(parse_choice("nope", &t).is_err());
    }

    #[test]
    fn saved_choice_is_per_apple_id() {
        let text = saved_text("AAAAAAAAAA", "Jo@Example.com");
        assert_eq!(parse_saved(&text, "jo@example.com").as_deref(), Some("AAAAAAAAAA"));
        assert_eq!(parse_saved(&text, "other@example.com"), None);
        assert_eq!(parse_saved("garbage", "a"), None);
    }
}
