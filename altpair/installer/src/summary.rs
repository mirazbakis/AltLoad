// The text for the end-of-run summary.

/// Days since 1970-01-01 to (year, month, day), proleptic Gregorian.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// "2026-11-25 14:03 UTC (in 7 days)". `now` is the current Unix time.
pub fn expiry(unix: i64, now: i64) -> String {
    let (y, mo, d) = civil_from_days(unix.div_euclid(86_400));
    let secs = unix.rem_euclid(86_400);
    let date = format!("{y:04}-{mo:02}-{d:02} {:02}:{:02} UTC", secs / 3600, secs % 3600 / 60);
    let left = unix - now;
    let rel = if left <= 0 {
        "already expired, check this iPhone's clock".to_string()
    } else if left < 3600 {
        "in under an hour".to_string()
    } else if left < 2 * 86_400 {
        format!("in {} hours", left / 3600)
    } else {
        format!("in {} days", (left + 43_200) / 86_400)
    };
    format!("{date} ({rel})")
}

/// Lines for the summary: app, team and expiry, leaving out what is unknown.
/// `team` is the label of the team used, and `free` says it is a free one.
pub fn lines(app: &str, team: &str, free: Option<bool>, expiration_unix: i64, now: i64) -> Vec<String> {
    let mut out = vec![format!("App: {app}")];
    if !team.is_empty() {
        out.push(format!("Team: {team}"));
    }
    if expiration_unix > 0 {
        out.push(format!("Expires: {}", expiry(expiration_unix, now)));
        // A free team's signing lasts 7 days; a paid one lasts a year. When the
        // team type is unknown, a short expiry says it.
        let free = free.unwrap_or(expiration_unix - now <= 8 * 86_400);
        if free {
            out.push("Free Apple IDs last 7 days. Run altpair again before then to renew.".into());
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(19_723), (2024, 1, 1));
        assert_eq!(civil_from_days(19_782), (2024, 2, 29));
        // 2026-11-18 12:00 UTC
        let now = 1795003200;
        assert!(expiry(now + 7 * 86_400, now).starts_with("2026-11-25 12:00 UTC (in 7 days)"));
    }

    #[test]
    fn relative_wording() {
        let now = 1_000_000;
        assert!(expiry(now - 5, now).contains("expired"));
        assert!(expiry(now + 600, now).contains("under an hour"));
        assert!(expiry(now + 5 * 3600, now).contains("in 5 hours"));
    }

    #[test]
    fn free_team_note() {
        let now = 1795003200;
        let free = lines("AltLoad 1.0", "Jo (ABCDE12345, free)", None, now + 7 * 86_400, now);
        assert_eq!(free[0], "App: AltLoad 1.0");
        assert_eq!(free[1], "Team: Jo (ABCDE12345, free)");
        assert!(free.iter().any(|l| l.contains("7 days. Run altpair")));
        let paid = lines("AltLoad", "", None, now + 300 * 86_400, now);
        assert_eq!(paid.len(), 2);
        assert_eq!(lines("AltLoad", "", None, 0, now), vec!["App: AltLoad".to_string()]);
        // The team type wins over the length of the signing.
        assert!(lines("A", "T", Some(false), now + 3 * 86_400, now).iter().all(|l| !l.contains("7 days")));
        assert!(lines("A", "T", Some(true), now + 300 * 86_400, now).iter().any(|l| l.contains("7 days")));
    }
}
