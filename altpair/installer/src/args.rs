// Command-line parsing. Kept free of I/O so it can be tested directly.

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Options {
    /// An IPA URL or a local path to install instead of AltLoad's latest release.
    pub ipa: Option<String>,
    /// Fetch a new pairing file even when one is saved.
    pub repair: bool,
    /// An anisette server to try first.
    pub anisette: Option<String>,
    /// A developer team ID to sign with, skipping the choice.
    pub team: Option<String>,
    /// Ask which team to use even when one was chosen before.
    pub choose_team: bool,
    /// Print debug detail.
    pub verbose: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    Run(Options),
    Help,
    Version,
}

pub const USAGE: &str = "\
Usage: altpair [options]

Installs AltLoad on this iPhone, signed
with your Apple ID. It needs:
  - LocalDevVPN connected
  - the pairing tool (altpair.wasm)
    running in rootshell, to give you
    a 6-digit transfer code

Steps: pairing file, Apple ID, team,
download, sign and install. A saved
pairing file and team are reused, so a
second run is quicker.

Options:
  --ipa <url|path>  Install this IPA
                    instead of AltLoad's
                    latest release
  --repair          Fetch a new pairing
                    file
  --anisette <url>  Anisette server to
                    try first (https)
  --team <ID>       Developer team to
                    sign with. Without
                    it you pick from the
                    list when you have
                    more than one team
  --choose-team     Ask again which team
  -v, --verbose     Print debug detail
  -h, --help        Show this help
  -V, --version     Show the version

Environment:
  ALTPAIR_APPLE_ID    Apple ID email
  ALTPAIR_PASSWORD    Apple ID password

Two-factor code: type r to resend,
s for a text message, d for devices.

Files are kept in ~/.altload.
Exit codes: 0 ok, 1 failed, 2 usage.
";

/// Parses the arguments after the program name. `--help` and `--version` win as
/// soon as they are seen; anything unknown is an error.
pub fn parse_args<I, S>(args: I) -> Result<Command, String>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut opts = Options::default();
    let mut it = args.into_iter().map(Into::into);
    while let Some(arg) = it.next() {
        let (name, inline) = match arg.split_once('=') {
            Some((n, v)) if n.starts_with("--") => (n.to_string(), Some(v.to_string())),
            _ => (arg.clone(), None),
        };
        match name.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "-V" | "--version" => return Ok(Command::Version),
            "--repair" if inline.is_none() => opts.repair = true,
            "--choose-team" if inline.is_none() => opts.choose_team = true,
            "-v" | "--verbose" if inline.is_none() => opts.verbose = true,
            "--ipa" | "--anisette" | "--team" => {
                let value = match inline {
                    Some(v) => v,
                    None => it.next().ok_or_else(|| format!("{name} needs a value"))?,
                };
                if value.trim().is_empty() || (value.starts_with("--") && value.len() > 2) {
                    return Err(format!("{name} needs a value"));
                }
                let slot = match name.as_str() {
                    "--ipa" => &mut opts.ipa,
                    "--team" => &mut opts.team,
                    _ => &mut opts.anisette,
                };
                if slot.is_some() {
                    return Err(format!("{name} given twice"));
                }
                *slot = Some(value.trim().to_string());
            }
            _ => return Err(format!("unknown option: {arg}")),
        }
    }
    if let Some(team) = &opts.team {
        if !team.bytes().all(|b| b.is_ascii_alphanumeric()) {
            return Err("--team takes a team ID such as ABCDE12345".into());
        }
    }
    if let Some(url) = &opts.anisette {
        if !url.to_ascii_lowercase().starts_with("https://") {
            return Err("--anisette must be an https:// URL".into());
        }
    }
    Ok(Command::Run(opts))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Result<Command, String> {
        parse_args(args.iter().copied())
    }

    #[test]
    fn no_arguments_runs_with_defaults() {
        assert_eq!(run(&[]), Ok(Command::Run(Options::default())));
    }

    #[test]
    fn help_and_version() {
        assert_eq!(run(&["--help"]), Ok(Command::Help));
        assert_eq!(run(&["-h"]), Ok(Command::Help));
        assert_eq!(run(&["--version"]), Ok(Command::Version));
        assert_eq!(run(&["-V"]), Ok(Command::Version));
        assert_eq!(run(&["--repair", "--help"]), Ok(Command::Help));
    }

    #[test]
    fn values_in_both_forms() {
        let want = Options {
            ipa: Some("/tmp/a.ipa".into()),
            repair: true,
            anisette: Some("https://ani.example".into()),
            team: None,
            choose_team: false,
            verbose: false,
        };
        assert_eq!(
            run(&["--ipa", "/tmp/a.ipa", "--repair", "--anisette", "https://ani.example"]),
            Ok(Command::Run(want))
        );
        let Ok(Command::Run(o)) = run(&["--ipa=https://x/y.ipa"]) else { panic!() };
        assert_eq!(o.ipa.as_deref(), Some("https://x/y.ipa"));
    }

    #[test]
    fn team_flags() {
        let Ok(Command::Run(o)) = run(&["--team", "ABCDE12345", "--choose-team"]) else { panic!() };
        assert_eq!(o.team.as_deref(), Some("ABCDE12345"));
        assert!(o.choose_team);
        let Ok(Command::Run(o)) = run(&["--team=abc123"]) else { panic!() };
        assert_eq!(o.team.as_deref(), Some("abc123"));
        assert!(run(&["--team"]).is_err());
        assert!(run(&["--team", "a b"]).is_err());
        assert!(run(&["--team", "a", "--team", "b"]).is_err());
    }

    #[test]
    fn verbose_flag() {
        let Ok(Command::Run(o)) = run(&["-v"]) else { panic!() };
        assert!(o.verbose);
        let Ok(Command::Run(o)) = run(&["--verbose", "--repair"]) else { panic!() };
        assert!(o.verbose && o.repair);
        assert!(run(&["--verbose=1"]).is_err());
    }

    #[test]
    fn usage_fits_the_phone_width() {
        assert!(USAGE.lines().all(|l| l.chars().count() <= crate::ui::WIDTH));
    }

    #[test]
    fn bad_input_is_an_error() {
        assert!(run(&["--bogus"]).is_err());
        assert!(run(&["extra"]).is_err());
        assert!(run(&["--ipa"]).is_err());
        assert!(run(&["--ipa", "--repair"]).is_err());
        assert!(run(&["--ipa="]).is_err());
        assert!(run(&["--ipa", "a", "--ipa", "b"]).is_err());
        assert!(run(&["--repair=yes"]).is_err());
        assert!(run(&["--anisette", "http://plain.example"]).is_err());
    }
}
