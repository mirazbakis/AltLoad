//! Command-line options.

use std::net::Ipv4Addr;

pub const DEFAULT_PORT: u16 = 49207;

pub const USAGE: &str = "\
altpair: pair this iPhone with
itself, then pass the pairing file to
the installer.

usage:
  ifconfig en0 | ./altpair.wasm
  ./altpair.wasm --ip 192.168.1.5

options:
  --ip A.B.C.D  Wi-Fi address to use
  --port N      pairing port (49207)
  --repair      pair again even if
                rp_pairing_file.plist
                exists
  -h, --help    show this help

exit codes: 0 ok, 1 failure, 2 usage";

#[derive(Debug, PartialEq, Eq)]
pub struct Options {
    pub ip: Option<Ipv4Addr>,
    pub port: u16,
    pub repair: bool,
    pub help: bool,
}

pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Result<Options, String> {
    let mut o = Options { ip: None, port: DEFAULT_PORT, repair: false, help: false };
    let mut it = args.into_iter();
    while let Some(arg) = it.next() {
        let (flag, inline) = match arg.split_once('=') {
            Some((f, v)) if f.starts_with("--") => (f.to_string(), Some(v.to_string())),
            _ => (arg.clone(), None),
        };
        let mut value = |name: &str| -> Result<String, String> {
            inline
                .clone()
                .or_else(|| it.next())
                .ok_or_else(|| format!("{name} needs a value"))
        };
        match flag.as_str() {
            "-h" | "--help" => o.help = true,
            "--repair" => o.repair = true,
            "--ip" => {
                let v = value("--ip")?;
                let ip: Ipv4Addr = v.parse().map_err(|_| format!("bad --ip: {v}"))?;
                o.ip = Some(ip);
            }
            "--port" => {
                let v = value("--port")?;
                o.port = match v.parse::<u16>() {
                    Ok(p) if p != 0 => p,
                    _ => return Err(format!("bad --port: {v}")),
                };
            }
            _ => return Err(format!("unknown option: {arg}")),
        }
    }
    Ok(o)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(a: &[&str]) -> Result<Options, String> {
        parse(a.iter().map(|s| s.to_string()))
    }

    #[test]
    fn defaults() {
        assert_eq!(
            p(&[]).unwrap(),
            Options { ip: None, port: 49207, repair: false, help: false }
        );
    }

    #[test]
    fn all_options() {
        let o = p(&["--ip", "10.0.0.2", "--port=50000", "--repair"]).unwrap();
        assert_eq!(o.ip, Some(Ipv4Addr::new(10, 0, 0, 2)));
        assert_eq!(o.port, 50000);
        assert!(o.repair);
        assert!(p(&["-h"]).unwrap().help);
        assert_eq!(p(&["--ip=1.2.3.4"]).unwrap().ip, Some(Ipv4Addr::new(1, 2, 3, 4)));
    }

    #[test]
    fn errors() {
        assert!(p(&["--ip"]).is_err());
        assert!(p(&["--ip", "1.2.3"]).is_err());
        assert!(p(&["--port", "0"]).is_err());
        assert!(p(&["--port", "70000"]).is_err());
        assert!(p(&["--bogus"]).is_err());
    }

    #[test]
    fn usage_fits_40_columns() {
        assert!(USAGE.lines().all(|l| l.chars().count() <= 40));
    }
}
