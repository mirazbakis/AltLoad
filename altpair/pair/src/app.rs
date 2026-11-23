//! The program itself: pair over Wi-Fi, save the pairing file, then serve it
//! to the installer on the loopback interface.

use std::io::Write;
use std::net::Ipv4Addr;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};

use crate::abi::errno_text;
use crate::args::{self, Options};
use crate::host::{self, Socket, TcpConn};
use crate::{bigdigits, dns, handoff, hints, ifconfig, plistfix};

/// Name shown in Settings ("Pair with AltLoad") and model reported to iOS.
const HOST_NAME: &str = "AltLoad";
const HOST_MODEL: &str = "Mac17,7";
const PAIRING_FILE: &str = "rp_pairing_file.plist";
/// Where the guide saves `ifconfig en0` output; read when no file is named.
const IFCONFIG_FILE: &str = "if.txt";
const MDNS_GROUP: Ipv4Addr = Ipv4Addr::new(224, 0, 0, 251);
const MDNS_PORT: u16 = 5353;
const ANNOUNCE_COUNT: usize = 3;
/// Tries per packet before an announcement counts as failed.
const SEND_TRIES: usize = 3;

static VERBOSE: AtomicBool = AtomicBool::new(false);

/// Debug detail, printed with --verbose.
macro_rules! debug {
    ($($arg:tt)*) => {
        if VERBOSE.load(Ordering::Relaxed) {
            println!("  [debug] {}", format!($($arg)*));
        }
    };
}

enum Fail {
    Usage(String),
    Other(String),
}

pub fn main() -> i32 {
    host::cooked_terminal();
    let opts = match args::parse(std::env::args().skip(1)) {
        Ok(o) => o,
        Err(e) => {
            eprintln!("{e}");
            eprintln!("Try --help.");
            return 2;
        }
    };
    if opts.help {
        println!("{}", args::USAGE);
        return 0;
    }
    if opts.version {
        println!("altpair.wasm {}", env!("CARGO_PKG_VERSION"));
        return 0;
    }
    VERBOSE.store(opts.verbose, Ordering::Relaxed);
    debug!("altpair.wasm {}", env!("CARGO_PKG_VERSION"));

    let plist = if !opts.repair && Path::new(PAIRING_FILE).exists() {
        match std::fs::read(PAIRING_FILE) {
            Ok(b) => {
                println!("Using saved {PAIRING_FILE}");
                println!("(--repair to pair again)");
                b
            }
            Err(e) => {
                println!("Cannot read {PAIRING_FILE}: {e}");
                return 1;
            }
        }
    } else {
        match pair(&opts) {
            Ok(b) => b,
            Err(Fail::Usage(m)) => {
                println!("{m}");
                return 2;
            }
            Err(Fail::Other(m)) => {
                println!("Failed: {m}");
                println!("(--verbose shows more detail)");
                return 1;
            }
        }
    };

    serve(&plist)
}

/// Finds the Wi-Fi address: `--ip`, then an ifconfig file (the one named on the
/// command line, or `if.txt` in this folder), then `ifconfig` output on stdin.
fn wifi_address(opts: &Options) -> Result<Ipv4Addr, Fail> {
    if let Some(ip) = opts.ip {
        return Ok(ip);
    }

    // Read the file directly: rootshell doesn't always end a `< if.txt` redirect,
    // and reading stdin then waits forever.
    let named = opts.file.is_some();
    let path = opts.file.clone().unwrap_or_else(|| IFCONFIG_FILE.to_string());
    match std::fs::read(&path) {
        Ok(bytes) => {
            debug!("read {} bytes of ifconfig output from {path}", bytes.len());
            let text = String::from_utf8_lossy(&bytes);
            return ifconfig::parse_inet(&text)
                .ok_or_else(|| Fail::Usage(hints::no_address(text.trim().is_empty())));
        }
        Err(e) if named => return Err(Fail::Usage(format!("Couldn't read {path}: {e}"))),
        Err(e) => debug!("no {path} ({e}); reading stdin"),
    }

    eprintln!("Reading ifconfig from stdin...");
    eprintln!("(If this stays here, press Ctrl-C and run: ./altpair.wasm --ip A.B.C.D)");
    let (ip, read) = ifconfig::read_until_address(&mut std::io::stdin(), 256 * 1024);
    debug!("read {read} bytes of ifconfig output");
    ip.ok_or_else(|| Fail::Usage(hints::no_address(read == 0)))
}

fn announce(a: &dns::Announcement, times: usize) -> Result<(), String> {
    let packet = dns::announcement_packet(a)?;
    let mut last_err = None;
    let mut sent = 0;
    for i in 0..times {
        if i > 0 {
            std::thread::sleep(Duration::from_secs(1));
        }
        for attempt in 1..=SEND_TRIES {
            match host::udp_send_once(&packet, MDNS_GROUP, MDNS_PORT) {
                Ok(()) => {
                    debug!("mDNS packet {} sent ({} bytes)", i + 1, packet.len());
                    sent += 1;
                    break;
                }
                Err(e) => {
                    debug!("mDNS send {} try {attempt}: {e}", i + 1);
                    last_err = Some(e);
                    std::thread::sleep(Duration::from_millis(400));
                }
            }
        }
    }
    match (sent, last_err) {
        (0, Some(e)) => Err(e),
        _ => Ok(()),
    }
}

fn show_pin(pin: &str) {
    println!();
    println!("Enter this code in Settings:");
    println!();
    for row in bigdigits::render(pin) {
        println!("  {row}");
    }
    println!();
    println!("Code: {pin}");
    let _ = std::io::stdout().flush();
}

fn pair(opts: &Options) -> Result<Vec<u8>, Fail> {
    let ip = wifi_address(opts)?;
    println!("[1/3] Wi-Fi address: {ip}");

    let listener = host::tcp_listen(Ipv4Addr::UNSPECIFIED, opts.port)
        .map_err(|e| Fail::Other(hints::listen(&e)))?;
    debug!("listening on 0.0.0.0:{}", opts.port);

    let mut pairing_file = RpPairingFile::generate(HOST_NAME);
    let host_info = PairableHostInfo::generate(HOST_NAME, HOST_MODEL);
    let instance = pairing_file.identifier.clone();
    let host_label = format!("altload-{}", instance.get(..8).unwrap_or("host"));
    let mut ann = dns::Announcement {
        instance: instance.clone(),
        host_label,
        port: opts.port,
        txt: host_info.mdns_txt_records(&instance),
        ip,
        ttl: dns::ANNOUNCE_TTL,
    };

    println!("[2/3] Announcing on port {}...", opts.port);
    announce(&ann, ANNOUNCE_COUNT).map_err(|e| Fail::Other(hints::mdns(&e)))?;

    println!();
    println!("On this iPhone open Settings >");
    println!("Privacy & Security >");
    println!("Developer Mode and tap");
    println!("\"Pair with {HOST_NAME}\".");
    println!();
    println!("[3/3] Waiting for the iPhone...");
    println!("Nothing after a minute? Check Wi-Fi,");
    println!("update rootshell (1.0.16-177+),");
    println!("then Ctrl-C and run again.");
    let _ = std::io::stdout().flush();

    let stream = listener
        .accept()
        .map_err(|e| Fail::Other(format!("accept: {}", errno_text(e))))?;
    drop(listener);
    println!("Connected. Pairing...");
    debug!("iPhone connected");

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_time()
        .build()
        .map_err(|e| Fail::Other(format!("runtime: {e}")))?;
    let peer = rt
        .block_on(async {
            let socket = RpPairingSocket::new_device(TcpConn(stream));
            let mut host = PairableHost::new(socket, host_info);
            host.accept(&mut pairing_file, |pin| async move { show_pin(&pin) })
                .await
        })
        .map_err(|e| Fail::Other(hints::pairing(&e.to_string())))?;

    // Withdraw the "Pair with" row now that pairing is done.
    ann.ttl = 0;
    let _ = announce(&ann, 1);

    let bytes = plistfix::with_udid(&pairing_file.to_bytes(), &peer.remotepairing_udid)
        .map_err(Fail::Other)?;
    std::fs::write(PAIRING_FILE, &bytes)
        .map_err(|e| Fail::Other(format!("save {PAIRING_FILE}: {e}")))?;

    println!();
    println!("Paired with {}.", peer.name);
    println!("Saved {PAIRING_FILE}");
    Ok(bytes)
}

fn random_u32() -> u32 {
    let mut b = [0u8; 4];
    if getrandom::getrandom(&mut b).is_err() {
        // The WASI random source failing is unexpected; fall back to the clock.
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos() ^ (d.as_secs() as u32))
            .unwrap_or(0);
        return t;
    }
    u32::from_ne_bytes(b)
}

/// Serves the pairing file on 127.0.0.1 until the tab is closed, or until too
/// many wrong codes arrive.
fn serve(plist: &[u8]) -> i32 {
    let listener = match host::tcp_listen(Ipv4Addr::LOCALHOST, handoff::PORT) {
        Ok(l) => l,
        Err(e) => {
            println!("Hand-off failed: {e}");
            return 1;
        }
    };
    let code = handoff::code_from(random_u32);
    let reply = handoff::ok_reply(plist);

    println!();
    println!("Open the installer and enter");
    println!("this transfer code:");
    println!();
    for row in bigdigits::render(&code) {
        println!("  {row}");
    }
    println!();
    println!("Transfer code: {code}");
    println!("Keep this tab open. Ctrl-C ends.");
    let _ = std::io::stdout().flush();

    let mut wrong = 0u32;
    loop {
        let conn: Socket = match listener.accept() {
            Ok(c) => c,
            Err(e) => {
                println!("Hand-off stopped: {}", errno_text(e));
                return 1;
            }
        };
        match handoff::read_request(|buf| conn.recv(buf)) {
            handoff::Request::Empty => continue,
            handoff::Request::Line(line) if handoff::is_valid_request(&line, &code) => {
                match conn.send_all(&reply) {
                    Ok(()) => println!("Sent pairing file ({} B).", plist.len()),
                    Err(e) => println!("Send failed: {}", errno_text(e)),
                }
            }
            _ => {
                let _ = conn.send_all(handoff::NO);
                wrong += 1;
                println!("Wrong transfer code ({wrong}/{}).", handoff::MAX_WRONG);
                if wrong >= handoff::MAX_WRONG {
                    println!("Too many wrong codes;");
                    println!("stopped serving. Run again.");
                    return 1;
                }
            }
        }
        let _ = conn.shutdown_write();
        let _ = std::io::stdout().flush();
    }
}
