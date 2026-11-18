// Developer teams: list them with their membership, and pick the one the user chose.

use super::*;

use isideload::dev::device_type::dev_url;

/// A team with what kind of membership it has.
#[derive(Clone, Debug)]
pub(super) struct TeamInfo {
    pub(super) team: DeveloperTeam,
    /// "free", "individual", "organization" or "unknown".
    pub(super) kind: &'static str,
}

impl TeamInfo {
    pub(super) fn json(&self) -> serde_json::Value {
        serde_json::json!({
            "id": self.team.team_id,
            "name": self.team.name.clone().unwrap_or_default(),
            "type": self.team.r#type.clone().unwrap_or_default(),
            "kind": self.kind,
        })
    }
}

/// Personal teams on a free Apple ID are "Individual" with a single free
/// provisioning membership.
pub(super) fn team_kind(team_type: Option<&str>, memberships: &[String]) -> &'static str {
    match team_type {
        Some("Company/Organization") => "organization",
        Some("Individual") => {
            if memberships.len() == 1 && memberships[0].to_lowercase().contains("free") {
                "free"
            } else {
                "individual"
            }
        }
        _ => "unknown",
    }
}

fn team_from(dict: &plist::Dictionary) -> Option<TeamInfo> {
    let s = |k: &str| dict.get(k).and_then(|v| v.as_string()).map(str::to_string);
    let team_id = s("teamId")?;
    let memberships: Vec<String> = dict
        .get("memberships")
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|m| m.as_dictionary())
                .map(|m| m.get("name").and_then(|v| v.as_string()).unwrap_or_default().to_string())
                .collect()
        })
        .unwrap_or_default();
    let team_type = s("type");
    Some(TeamInfo {
        kind: team_kind(team_type.as_deref(), &memberships),
        team: DeveloperTeam { name: s("name"), team_id, r#type: team_type, status: s("status") },
    })
}

/// Every team on the Apple ID, in the order Apple lists them.
pub(super) async fn list_teams(dev: &mut DeveloperSession) -> Result<Vec<TeamInfo>, String> {
    let raw: Vec<plist::Dictionary> = dev
        .send_dev_request(&dev_url("listTeams", DeveloperDeviceType::Any), None, "teams")
        .await
        .map_err(|e| err("Couldn't load your developer teams", e))?;
    let teams: Vec<TeamInfo> = raw.iter().filter_map(team_from).collect();
    if teams.is_empty() {
        return Err("This Apple ID has no developer team.".into());
    }
    Ok(teams)
}

/// The team whose ID is `wanted`, else the first. The note says why the first
/// was used when a team was asked for and isn't there.
pub(super) fn pick_team(teams: &[TeamInfo], wanted: Option<&str>) -> Option<(TeamInfo, Option<String>)> {
    let first = teams.first()?.clone();
    let wanted = wanted.map(str::trim).filter(|w| !w.is_empty());
    let Some(wanted) = wanted else { return Some((first, None)) };
    match teams.iter().find(|t| t.team.team_id.eq_ignore_ascii_case(wanted)) {
        Some(team) => Some((team.clone(), None)),
        None => {
            let name = first.team.name.clone().unwrap_or_default();
            Some((
                first.clone(),
                Some(format!(
                    "Team {wanted} isn't on this Apple ID anymore, so {} ({}) was used.",
                    if name.is_empty() { "the first team" } else { name.as_str() },
                    first.team.team_id
                )),
            ))
        }
    }
}

/// Lists the teams and picks one, reporting which.
pub(super) async fn choose_team(
    dev: &mut DeveloperSession,
    wanted: Option<&str>,
    cbs: Callbacks,
) -> Result<(TeamInfo, Vec<TeamInfo>, Option<String>), String> {
    let teams = list_teams(dev).await?;
    let (team, note) = pick_team(&teams, wanted).ok_or("This Apple ID has no developer team.")?;
    let name = team.team.name.clone().unwrap_or_default();
    cbs.progress(&format!("Using team {} ({})", if name.is_empty() { "-" } else { &name }, team.team.team_id), -1.0);
    if let Some(note) = &note {
        cbs.progress(note, -1.0);
    }
    Ok((team, teams, note))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn team(id: &str, kind: &'static str) -> TeamInfo {
        TeamInfo {
            team: DeveloperTeam { name: Some(format!("Team {id}")), team_id: id.into(), r#type: None, status: None },
            kind,
        }
    }

    #[test]
    fn kinds_follow_type_and_membership() {
        assert_eq!(team_kind(Some("Individual"), &["Xcode Free Provisioning Program".into()]), "free");
        assert_eq!(team_kind(Some("Individual"), &["Apple Developer Program".into()]), "individual");
        assert_eq!(team_kind(Some("Individual"), &[]), "individual");
        assert_eq!(team_kind(Some("Company/Organization"), &[]), "organization");
        assert_eq!(team_kind(None, &[]), "unknown");
    }

    #[test]
    fn picks_the_wanted_team_or_the_first() {
        let teams = vec![team("AAA", "free"), team("BBB", "organization")];
        let (t, note) = pick_team(&teams, Some("BBB")).unwrap();
        assert_eq!(t.team.team_id, "BBB");
        assert!(note.is_none());

        let (t, note) = pick_team(&teams, Some("bbb")).unwrap();
        assert_eq!(t.team.team_id, "BBB");
        assert!(note.is_none());

        let (t, note) = pick_team(&teams, None).unwrap();
        assert_eq!(t.team.team_id, "AAA");
        assert!(note.is_none());

        let (t, note) = pick_team(&teams, Some("  ")).unwrap();
        assert_eq!(t.team.team_id, "AAA");
        assert!(note.is_none());

        let (t, note) = pick_team(&teams, Some("CCC")).unwrap();
        assert_eq!(t.team.team_id, "AAA");
        assert!(note.unwrap().contains("CCC"));

        assert!(pick_team(&[], Some("AAA")).is_none());
    }

    #[test]
    fn reads_a_listed_team() {
        let mut membership = plist::Dictionary::new();
        membership.insert("name".into(), plist::Value::String("Xcode Free Provisioning Program".into()));
        let mut dict = plist::Dictionary::new();
        dict.insert("teamId".into(), plist::Value::String("ABC123".into()));
        dict.insert("name".into(), plist::Value::String("Personal Team".into()));
        dict.insert("type".into(), plist::Value::String("Individual".into()));
        dict.insert("memberships".into(), plist::Value::Array(vec![plist::Value::Dictionary(membership)]));
        let info = team_from(&dict).unwrap();
        assert_eq!(info.team.team_id, "ABC123");
        assert_eq!(info.kind, "free");
        assert_eq!(info.json()["name"], "Personal Team");
        assert!(team_from(&plist::Dictionary::new()).is_none());
    }
}
