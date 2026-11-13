// Command-line parsing. Kept free of I/O so it can be tested directly.

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Options {
    /// An IPA URL or a local path to install instead of AltLoad's latest release.
    pub ipa: Option<String>,
    /// Fetch a new pairing file even when one is saved.
    pub repair: bool,
    /// An anisette server to try first.
    pub anisette: Option<String>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Command {
    Run(Options),
    Help,
    Version,
}

pub const USAGE: &str = "\
Usage: altpair [options]

Installs AltLoad on this iPhone, signed with
your Apple ID. Needs LocalDevVPN connected.

Options:
  --ipa <url|path>  Install this IPA instead
  --repair          Fetch a new pairing file
  --anisette <url>  Anisette server to try
  -h, --help        Show this help
  -V, --version     Show the version

Environment:
  ALTPAIR_APPLE_ID    Apple ID email
  ALTPAIR_PASSWORD    Apple ID password
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
            "--ipa" | "--anisette" => {
                let value = match inline {
                    Some(v) => v,
                    None => it.next().ok_or_else(|| format!("{name} needs a value"))?,
                };
                if value.trim().is_empty() || (value.starts_with("--") && value.len() > 2) {
                    return Err(format!("{name} needs a value"));
                }
                let slot = if name == "--ipa" { &mut opts.ipa } else { &mut opts.anisette };
                if slot.is_some() {
                    return Err(format!("{name} given twice"));
                }
                *slot = Some(value.trim().to_string());
            }
            _ => return Err(format!("unknown option: {arg}")),
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
        };
        assert_eq!(
            run(&["--ipa", "/tmp/a.ipa", "--repair", "--anisette", "https://ani.example"]),
            Ok(Command::Run(want))
        );
        let Ok(Command::Run(o)) = run(&["--ipa=https://x/y.ipa"]) else { panic!() };
        assert_eq!(o.ipa.as_deref(), Some("https://x/y.ipa"));
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
