// The RemotePairing tunnel from this iPhone to itself, through LocalDevVPN.

use super::*;

pub(super) async fn open_tunnel(cfg: &Config) -> Result<(AdapterHandle, RsdHandshake), String> {
    open_tunnel_to(&cfg.pairing_file_path, &cfg.host_name, &cfg.endpoints).await
}

pub(super) async fn open_tunnel_to(
    pairing_file_path: &str,
    host_name: &str,
    endpoints: &[Endpoint],
) -> Result<(AdapterHandle, RsdHandshake), String> {
    let mut rpf = RpPairingFile::read_from_file(pairing_file_path)
        .await
        .map_err(|e| err("Couldn't read the pairing file", e))?;

    // Try advertisements that prove they belong to the paired device first.
    let mut endpoints = endpoints.to_vec();
    if let Some(irk) = rpf.alt_irk().map(<[u8]>::to_vec) {
        endpoints.sort_by_key(|ep| !PeerDevice::validate_auth_tag(&irk, &ep.identifier, &ep.auth_tag));
    }
    if endpoints.is_empty() {
        return Err("No address to reach this iPhone was given.".into());
    }

    // A port a scan found earlier in this run of AltLoad goes first.
    if let (Some(port), Some(first)) = (*SCANNED_PORT.lock().unwrap(), endpoints.first().cloned()) {
        if !endpoints.iter().any(|ep| ep.port == port) {
            endpoints.insert(0, Endpoint { port, identifier: String::new(), auth_tag: String::new(), ..first });
        }
    }

    // The second connection (to the tunnel port remotepairingd just opened) sometimes
    // stalls right after LocalDevVPN connects. Starting over with a fresh listener
    // usually gets through, so try a few rounds before giving up.
    const ATTEMPTS: u32 = 3;
    let mut last_error = String::new();
    let mut reached_service = false;
    let mut scanned = false;
    for attempt in 1..=ATTEMPTS {
        for ep in &endpoints {
            match connect_endpoint(ep, host_name, &mut rpf).await {
                Ok(tunnel) => return Ok(tunnel),
                Err(e) => {
                    // A rejected pairing file won't fix itself; stop right away.
                    if e.contains("no longer accepts the pairing file") {
                        return Err(format!("Couldn't open a tunnel to this device ({e}).\n\n{REPAIR_STEPS}"));
                    }
                    reached_service |= past_pair_verify(&e);
                    // Keep the most telling error: a refused port only means nothing listens there.
                    let refused = e.contains("refused");
                    if !refused || last_error.is_empty() || last_error.contains("refused") {
                        last_error = format!("{}:{}: {e}", ep.host, ep.port);
                    }
                }
            }
        }

        // remotepairingd takes whatever port is free when it starts. If none of the
        // given ports led to it, look for it on the rest of the iPhone's ports once.
        if !reached_service && !scanned {
            scanned = true;
            if let Some(first) = endpoints.first() {
                let tried: Vec<u16> = endpoints.iter().map(|ep| ep.port).collect();
                match scan_for_pairing_service(first, &tried, host_name, &mut rpf).await {
                    Ok(Some(tunnel)) => return Ok(tunnel),
                    Ok(None) => {
                        last_error = format!(
                            "{}: nothing answered as the pairing service on ports {}–{}",
                            first.host,
                            SCAN_PORTS.start(),
                            SCAN_PORTS.end()
                        );
                    }
                    Err(e) => {
                        let steps = if e.contains("no longer accepts the pairing file") { REPAIR_STEPS } else { TUNNEL_STEPS };
                        return Err(format!("Couldn't open a tunnel to this device ({e}).\n\n{steps}"));
                    }
                }
            }
        }

        if attempt < ATTEMPTS {
            tokio::time::sleep(Duration::from_millis(1500 * attempt as u64)).await;
        }
    }
    Err(format!(
        "Couldn't open a tunnel to this device after {ATTEMPTS} tries ({last_error}).\n\n{TUNNEL_STEPS}"
    ))
}

/// What to try, in order, when the tunnel can't be opened.
const TUNNEL_STEPS: &str = "Try these in order:\n\
    1. Turn LocalDevVPN off and on again, then try again.\n\
    2. Turn off any other VPN, proxy or DNS-filter app.\n\
    3. Connect to Wi-Fi. On mobile data the tunnel often can't connect.\n\
    4. Check that Developer Mode is on (Settings › Privacy & Security).\n\
    5. Close AltLoad from the app switcher and open it again.\n\
    6. If it still fails, create a new pairing file in the Pair tab.";

/// What to try when the iPhone rejects the pairing file.
const REPAIR_STEPS: &str = "Try these in order:\n\
    1. Create a new pairing file in the Pair tab.\n\
    2. If Pair with AltLoad doesn't show up, restart the iPhone and try again.\n\
    3. Or make one with altpair.wasm --repair in rootshell and import it.";

/// Where a scan last found remotepairingd. Kept until AltLoad quits.
static SCANNED_PORT: Mutex<Option<u16>> = Mutex::new(None);

/// Held while a tunnel is being set up. Each FFI call runs its own runtime, and a
/// tokio mutex works across runtimes.
static HANDSHAKE: AsyncMutex<()> = AsyncMutex::const_new(());

/// Longest one tunnel setup may take (the timed steps alone add up to about 25 s).
const HANDSHAKE_LIMIT: Duration = Duration::from_secs(45);

/// Longest a caller waits for another setup to finish before it gives up.
const HANDSHAKE_WAIT: Duration = Duration::from_secs(2 * 45 + 10);

/// iOS hands out ports for its services from this range.
const SCAN_PORTS: std::ops::RangeInclusive<u16> = 49152..=65535;

/// lockdownd: open, but never the pairing service.
const NOT_PAIRING: [u16; 1] = [62078];

/// True when an error from `connect_endpoint` came after pair-verify succeeded,
/// so the port really was remotepairingd.
fn past_pair_verify(e: &str) -> bool {
    ["tunnel listener", "tunnel connect", "tunnel setup", "TLS-PSK", "tunnel client", "tunnel server", "RSD"]
        .iter()
        .any(|step| e.contains(step))
}

/// Knocks on every port in `SCAN_PORTS` (32 at a time; a closed one refuses at
/// once), then tries the pairing handshake on each one that's open. Ok(None) when
/// none of them is the pairing service.
async fn scan_for_pairing_service(
    like: &Endpoint,
    tried: &[u16],
    host_name: &str,
    rpf: &mut RpPairingFile,
) -> Result<Option<(AdapterHandle, RsdHandshake)>, String> {
    let ip = match tokio::net::lookup_host((like.host.as_str(), 0)).await.ok().and_then(|mut a| a.next()) {
        Some(addr) => addr.ip(),
        None => return Ok(None),
    };

    let open = open_ports(ip, tried).await;

    for port in open {
        let ep = Endpoint { port, identifier: String::new(), auth_tag: String::new(), ..like.clone() };
        match connect_endpoint(&ep, host_name, rpf).await {
            Ok(tunnel) => {
                *SCANNED_PORT.lock().unwrap() = Some(port);
                return Ok(Some(tunnel));
            }
            Err(e) if e.contains("no longer accepts the pairing file") => return Err(e),
            Err(_) => {}
        }
    }
    Ok(None)
}

/// The ports in `SCAN_PORTS` that accept a connection, skipping `tried` and
/// lockdownd. Knocks on 32 at a time; a closed port refuses at once.
async fn open_ports(ip: std::net::IpAddr, tried: &[u16]) -> Vec<u16> {
    let mut open: Vec<u16> = Vec::new();
    let mut ports = SCAN_PORTS.filter(|p| !tried.contains(p) && !NOT_PAIRING.contains(p));
    let mut tasks = tokio::task::JoinSet::new();
    let knock = async {
        loop {
            while tasks.len() < 32 {
                let Some(port) = ports.next() else { break };
                tasks.spawn(async move {
                    let addr = SocketAddr::new(ip, port);
                    match tokio::time::timeout(Duration::from_millis(1500), TcpStream::connect(addr)).await {
                        Ok(Ok(_)) => Some(port),
                        _ => None,
                    }
                });
            }
            match tasks.join_next().await {
                Some(Ok(Some(port))) => open.push(port),
                Some(_) => {}
                None => break,
            }
        }
    };
    // A tunnel that drops packets instead of refusing them would make this slow; cap it.
    let _ = tokio::time::timeout(Duration::from_secs(60), knock).await;
    tasks.abort_all();
    open.sort_unstable();

    open
}

#[cfg(test)]
mod scan_tests {
    use super::*;

    #[tokio::test(flavor = "multi_thread")]
    async fn finds_an_open_port_quickly() {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        assert!(SCAN_PORTS.contains(&port), "the OS gave a port outside the scan range: {port}");
        tokio::spawn(async move { loop { let _ = listener.accept().await; } });
        let started = std::time::Instant::now();
        let open = open_ports("127.0.0.1".parse().unwrap(), &[]).await;
        println!("scanned in {:?}, open: {open:?}", started.elapsed());
        assert!(open.contains(&port));
        assert!(started.elapsed() < Duration::from_secs(30));
    }

    #[test]
    fn knows_which_errors_reached_the_service() {
        assert!(past_pair_verify("tunnel connect timed out"));
        assert!(past_pair_verify("RSD handshake: oops"));
        assert!(!past_pair_verify("Connection refused (os error 61)"));
        assert!(!past_pair_verify("pair-verify timed out"));
    }
}

pub(super) async fn connect_endpoint(
    ep: &Endpoint,
    host_name: &str,
    rpf: &mut RpPairingFile,
) -> Result<(AdapterHandle, RsdHandshake), String> {
    // One handshake at a time: when an install and the JIT tab open tunnels together,
    // their pair-verify and listener steps interleave on remotepairingd and both stall.
    // The whole setup is time-limited so a stuck step can't hold the lock for good.
    let _turn = match tokio::time::timeout(HANDSHAKE_WAIT, HANDSHAKE.lock()).await {
        Ok(guard) => guard,
        Err(_) => return Err("timed out waiting for another connection to this device. Wait a moment and try again; if it keeps happening, close AltLoad from the app switcher and open it again".into()),
    };
    match tokio::time::timeout(HANDSHAKE_LIMIT, connect_endpoint_locked(ep, host_name, rpf)).await {
        Ok(result) => result,
        Err(_) => Err("tunnel setup timed out".into()),
    }
}

async fn connect_endpoint_locked(
    ep: &Endpoint,
    host_name: &str,
    rpf: &mut RpPairingFile,
) -> Result<(AdapterHandle, RsdHandshake), String> {
    let addrs: Vec<SocketAddr> = tokio::net::lookup_host((ep.host.as_str(), ep.port))
        .await
        .map_err(|e| err("lookup", e))?
        .collect();

    let mut last = "no addresses".to_string();
    for addr in addrs {
        let stream = match tokio::time::timeout(Duration::from_secs(5), TcpStream::connect(addr)).await {
            Ok(Ok(s)) => s,
            Ok(Err(e)) => {
                last = e.to_string();
                continue;
            }
            Err(_) => {
                last = "timed out".into();
                continue;
            }
        };

        let mut rpc = RemotePairingClient::new(RpPairingSocket::new(stream), host_name);
        // A port that isn't remotepairingd may accept the connection and never answer.
        match tokio::time::timeout(Duration::from_secs(8), rpc.attempt_pair_verify()).await {
            Ok(Ok(_)) => {}
            Ok(Err(e)) => return Err(err("pair-verify handshake", e)),
            Err(_) => return Err("pair-verify timed out".into()),
        }
        // Only verify: never fall back to a fresh pair-setup here.
        rpc.validate_pairing(rpf).await.map_err(|_| {
            "this iPhone no longer accepts the pairing file".to_string()
        })?;

        let tunnel_port = rpc
            .create_tcp_listener()
            .await
            .map_err(|e| err("tunnel listener", e))?;
        let mut tunnel_addr = addr;
        tunnel_addr.set_port(tunnel_port);
        let tunnel_stream =
            match tokio::time::timeout(Duration::from_secs(10), TcpStream::connect(tunnel_addr)).await {
                Ok(Ok(s)) => s,
                Ok(Err(e)) => return Err(err("tunnel connect", e)),
                Err(_) => return Err("tunnel connect timed out".into()),
            };
        let tunnel = connect_tls_psk_tunnel_native(tunnel_stream, rpc.encryption_key())
            .await
            .map_err(|e| err("TLS-PSK tunnel", e))?;

        let client_ip: std::net::IpAddr = tunnel
            .info
            .client_address
            .parse()
            .map_err(|e| err("tunnel client address", e))?;
        let server_ip: std::net::IpAddr = tunnel
            .info
            .server_address
            .parse()
            .map_err(|e| err("tunnel server address", e))?;
        let mtu = tunnel.info.mtu as usize;
        let rsd_port = tunnel.info.server_rsd_port;

        let raw = tunnel.into_inner();
        let mut adapter = idevice::tcp::adapter::Adapter::new(Box::new(raw), client_ip, server_ip);
        // Capped like idevice does: a larger MSS stalls the tunnel on recent iOS.
        adapter.set_mss(mtu.min(8192).saturating_sub(60));
        let mut adapter = adapter.to_async_handle();

        let rsd_stream = adapter
            .connect(rsd_port)
            .await
            .map_err(|e| err("RSD connect", e))?;
        let handshake = RsdHandshake::new(rsd_stream)
            .await
            .map_err(|e| err("RSD handshake", e))?;
        return Ok((adapter, handshake));
    }
    Err(last)
}
