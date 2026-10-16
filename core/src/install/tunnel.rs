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

    let mut last_error = String::new();
    for ep in endpoints {
        match connect_endpoint(&ep, host_name, &mut rpf).await {
            Ok(tunnel) => return Ok(tunnel),
            Err(e) => last_error = format!("{}:{}: {e}", ep.host, ep.port),
        }
    }
    Err(format!(
        "Couldn't open a tunnel to this device ({last_error}). Make sure LocalDevVPN is connected \
         and Developer Mode is on."
    ))
}

pub(super) async fn connect_endpoint(
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
        rpc.attempt_pair_verify()
            .await
            .map_err(|e| err("pair-verify handshake", e))?;
        // Only verify: never fall back to a fresh pair-setup here.
        rpc.validate_pairing(rpf).await.map_err(|_| {
            "this iPhone no longer accepts the pairing file. Create a new one in the Pair tab.".to_string()
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
        adapter.set_mss(mtu.saturating_sub(60));
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
