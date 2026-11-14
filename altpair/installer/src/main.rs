// altpair: installs AltLoad onto the iPhone it runs on, from a Linux shell on that
// iPhone (with LocalDevVPN connected), signed with the user's own Apple ID.
//
//   1. Pairing file: ~/.altload/rp_pairing_file.plist, or fetched from the
//      pairing tool over loopback with a 6-digit transfer code.
//   2. Apple ID: email and password from the environment or prompts.
//   3. The IPA: AltLoad's latest release, or --ipa.
//   4. Install: AltLoad's core signs in, opens the tunnel to this iPhone,
//      signs the app and installs it.

mod anisette;
mod args;
mod download;
mod handoff;
mod prompts;
mod session;
mod term;
mod ui;

use std::fs;
use std::io::Write;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use args::{Command, Options};
use download::IpaSource;

const PAIRING_FILE: &str = "rp_pairing_file.plist";
const SERVER_ID_FILE: &str = "server_id";
const PAIRING_TRIES: u32 = 3;

fn main() -> ExitCode {
    let opts = match args::parse_args(std::env::args().skip(1)) {
        Ok(Command::Help) => {
            print!("{}", args::USAGE);
            return ExitCode::SUCCESS;
        }
        Ok(Command::Version) => {
            println!("altpair {}", env!("CARGO_PKG_VERSION"));
            return ExitCode::SUCCESS;
        }
        Ok(Command::Run(opts)) => opts,
        Err(e) => {
            eprintln!("altpair: {e}");
            eprint!("{}", args::USAGE);
            return ExitCode::from(2);
        }
    };

    term::install_signal_handlers();
    // reqwest is built without a default TLS provider; use ring, as the core does.
    let _ = rustls::crypto::ring::default_provider().install_default();

    match run(opts) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!();
            ui::eprint_wrapped(&e);
            ExitCode::from(1)
        }
    }
}

fn run(opts: Options) -> Result<(), String> {
    let state = state_dir()?;

    // 1. Pairing file.
    ui::step(1, "Pairing file");
    let pairing = state.join(PAIRING_FILE);
    if pairing.is_file() && !opts.repair {
        ui::result("Using the saved one");
    } else {
        fetch_pairing(&pairing)?;
        ui::result("Saved");
    }

    // 2. Apple ID.
    ui::step(2, "Apple ID");
    let apple_id = match std::env::var("ALTPAIR_APPLE_ID") {
        Ok(v) if !v.trim().is_empty() => v.trim().to_string(),
        _ => ask_nonempty("      Email: ", false)?,
    };
    let password = match std::env::var("ALTPAIR_PASSWORD") {
        Ok(v) if !v.is_empty() => v,
        _ => ask_nonempty("      Password: ", true)?,
    };
    ui::result(&format!("Using {apple_id}"));

    // 3. The IPA.
    ui::step(3, "Download AltLoad");
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| format!("Couldn't start: {e}"))?;
    let client = download::client()?;
    let source = download::ipa_source(opts.ipa.as_deref().unwrap_or(download::LATEST_IPA));
    let ipa = match source {
        IpaSource::Path(path) => {
            download::looks_like_zip(&path)?;
            ui::result("Using the local file");
            fs::canonicalize(&path).unwrap_or(path)
        }
        IpaSource::Url(url) => {
            let dest = state.join("downloads").join("AltLoad.ipa");
            let mut progress = ui::Progress::new(term::is_tty(libc::STDOUT_FILENO));
            let fetched = rt.block_on(download::fetch(&client, &url, &dest, |f| progress.write("Downloading", f)));
            progress.close();
            fetched?;
            download::looks_like_zip(&dest)?;
            let size = fs::metadata(&dest).map(|m| m.len()).unwrap_or(0);
            ui::result(&format!("Downloaded ({:.1} MB)", size as f64 / 1_000_000.0));
            dest
        }
    };

    // 4. Install.
    ui::step(4, "Install");
    let anisette = rt.block_on(anisette::sign_in_list(&client, opts.anisette.as_deref()));
    drop(rt);
    let req = session::Request {
        apple_id,
        password,
        anisette,
        pairing_file: pairing.to_string_lossy().into_owned(),
        ipa: ipa.to_string_lossy().into_owned(),
        server_id: server_id(&state)?,
    };
    match session::run(req) {
        Ok(app) => {
            let name = if app.app_name.is_empty() { "AltLoad".to_string() } else { app.app_name };
            ui::result("Done");
            println!();
            if app.app_version.is_empty() {
                ui::print_wrapped(&format!("Installed {name}."));
            } else {
                ui::print_wrapped(&format!("Installed {name} {}.", app.app_version));
            }
            ui::print_wrapped(
                "Trust your Apple ID in Settings › General › VPN & Device Management, then open AltLoad.",
            );
            Ok(())
        }
        Err(e) => Err(failure_text(&e)),
    }
}

/// Adds a hint to failures the user can act on from here. The core's messages
/// are written for the app, so its Settings paths are swapped for altpair's options.
fn failure_text(e: &str) -> String {
    let e = e
        .replace("pick a different server in Settings › Anisette", "pick a different server with --anisette <url>")
        .replace("Settings › Anisette", "--anisette <url>");
    let lower = e.to_lowercase();
    if lower.contains("pairing file") {
        format!("{e}\n\nRun altpair --repair to fetch a new pairing file.")
    } else if e.contains("--anisette") {
        e
    } else if lower.contains("anisette") || e.contains("-80045") || e.contains("-45061") {
        format!("{e}\n\nTry again in a few minutes, or pick a server with --anisette <url>.")
    } else if lower.contains("cannot submit code without knowing") || lower.contains("cannot resend code without knowing") {
        format!("{e}\n\nRun altpair again and choose d or s when asked where to get a code.")
    } else {
        e
    }
}

/// ~/.altload, readable only by this user.
fn state_dir() -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME")
        .filter(|h| !h.is_empty())
        .ok_or("HOME is not set.")?;
    let dir = PathBuf::from(home).join(".altload");
    fs::create_dir_all(dir.join("downloads")).map_err(|e| format!("Couldn't create {}: {e}", dir.display()))?;
    fs::set_permissions(&dir, fs::Permissions::from_mode(0o700))
        .map_err(|e| format!("Couldn't set permissions on {}: {e}", dir.display()))?;
    Ok(dir)
}

fn ask_nonempty(prompt: &str, secret: bool) -> Result<String, String> {
    loop {
        let line = if secret { term::read_secret(prompt) } else { term::read_line(prompt) }
            .map_err(|e| format!("Couldn't read input: {e}"))?
            .ok_or("No input. Run altpair in a terminal.")?;
        let value = if secret { line } else { line.trim().to_string() };
        if !value.is_empty() {
            return Ok(value);
        }
    }
}

/// Asks for the transfer code and fetches the pairing file, up to three tries.
fn fetch_pairing(dest: &Path) -> Result<(), String> {
    ui::note("Enter the 6-digit code the pairing tool shows.");
    for attempt in 1..=PAIRING_TRIES {
        let code = loop {
            let line = term::read_line("      Code: ")
                .map_err(|e| format!("Couldn't read input: {e}"))?
                .ok_or("No input. Run altpair in a terminal.")?;
            match handoff::normalize_code(line.trim()) {
                Some(code) => break code,
                None => println!("      The code is 6 digits."),
            }
        };
        match handoff::fetch(&code)? {
            handoff::Reply::Pairing(bytes) => {
                if !handoff::is_plist_dictionary(&bytes) {
                    return Err("The pairing tool sent something that isn't a pairing file.".into());
                }
                return save_private(dest, &bytes);
            }
            handoff::Reply::Refused if attempt < PAIRING_TRIES => {
                println!("      That code wasn't accepted. Try again.");
            }
            handoff::Reply::Refused => {}
        }
    }
    Err("The pairing tool didn't accept the code. Check the code it shows and run altpair again.".into())
}

/// Writes a file only this user can read, replacing any old one in one step.
fn save_private(dest: &Path, bytes: &[u8]) -> Result<(), String> {
    let tmp = dest.with_extension("tmp");
    let _ = fs::remove_file(&tmp);
    let write = || -> std::io::Result<()> {
        let mut f = fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&tmp)?;
        f.write_all(bytes)?;
        f.sync_all()?;
        fs::rename(&tmp, dest)
    };
    write().map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("Couldn't save {}: {e}", dest.display())
    })
}

/// A stable ID written into the app as ALTServerID. Mirrors InstallController.serverID in
/// ios/App/Core/Install/InstallController.swift: a random UUID string, made once and kept.
fn server_id(state: &Path) -> Result<String, String> {
    let path = state.join(SERVER_ID_FILE);
    if let Ok(saved) = fs::read_to_string(&path) {
        let saved = saved.trim();
        if !saved.is_empty() {
            return Ok(saved.to_string());
        }
    }
    let mut bytes = [0u8; 16];
    fs::File::open("/dev/urandom")
        .and_then(|mut f| std::io::Read::read_exact(&mut f, &mut bytes))
        .map_err(|e| format!("Couldn't read random bytes: {e}"))?;
    let id = uuid_v4(bytes);
    save_private(&path, id.as_bytes())?;
    Ok(id)
}

/// Formats random bytes as an uppercase version-4 UUID, like Foundation's UUID().uuidString.
fn uuid_v4(mut b: [u8; 16]) -> String {
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let hex: String = b.iter().map(|x| format!("{x:02X}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uuid_format() {
        let id = uuid_v4([0xff; 16]);
        assert_eq!(id, "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF");
        let id = uuid_v4([0; 16]);
        assert_eq!(id, "00000000-0000-4000-8000-000000000000");
    }

    #[test]
    fn hints() {
        assert!(failure_text("Couldn't read the pairing file: x").contains("--repair"));
        assert!(failure_text("Apple ID sign-in failed: anisette").contains("--anisette"));
        assert_eq!(failure_text("Install failed: x"), "Install failed: x");
        // The core's wording points at the app's Settings; altpair has --anisette instead.
        let refused = failure_text("Apple ID sign-in failed: … then pick a different server in Settings › Anisette. Too many …");
        assert!(refused.contains("with --anisette <url>"));
        assert!(!refused.contains("Settings"));
        assert_eq!(refused.matches("--anisette").count(), 1);
    }
}
