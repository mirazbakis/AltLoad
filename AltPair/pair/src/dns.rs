//! Hand-written DNS encoding for the mDNS announcement that makes this iPhone's
//! Settings show the "Pair with …" row, plus a tiny unicast query used only to
//! give a UDP socket a route.

use std::net::Ipv4Addr;

/// Bonjour service type the pairing host is published under (without `.local`).
pub const SERVICE_TYPE: [&str; 2] = ["_remotepairing-pairable-host", "_tcp"];
/// DNS-SD meta-query name that lists every service type on the link.
pub const SERVICES_META: [&str; 3] = ["_services", "_dns-sd", "_udp"];
pub const DOMAIN: &str = "local";

pub const TYPE_A: u16 = 1;
pub const TYPE_NS: u16 = 2;
pub const TYPE_PTR: u16 = 12;
pub const TYPE_TXT: u16 = 16;
pub const TYPE_SRV: u16 = 33;
pub const CLASS_IN: u16 = 1;
/// mDNS "cache flush" bit, set on records only this host owns.
pub const CACHE_FLUSH: u16 = 0x8000;
/// Flags for an unsolicited mDNS response: QR=1 (response), AA=1 (authoritative).
pub const RESPONSE_FLAGS: u16 = 0x8400;
/// Time-to-live used for every announced record (75 minutes).
pub const ANNOUNCE_TTL: u32 = 4500;

/// What to announce.
#[derive(Debug, Clone)]
pub struct Announcement {
    /// Service instance label (the pairing identifier).
    pub instance: String,
    /// Host label; the SRV target and A record name are `<host_label>.local`.
    pub host_label: String,
    pub port: u16,
    pub txt: Vec<(String, String)>,
    pub ip: Ipv4Addr,
    /// 4500 for an announcement, 0 for a goodbye that withdraws it.
    pub ttl: u32,
}

/// Appends a name made of `labels` followed by the root label. No compression.
pub fn encode_name(out: &mut Vec<u8>, labels: &[&str]) -> Result<(), String> {
    for label in labels {
        let bytes = label.as_bytes();
        if bytes.is_empty() || bytes.len() > 63 {
            return Err(format!("bad DNS label {label:?}"));
        }
        out.push(bytes.len() as u8);
        out.extend_from_slice(bytes);
    }
    out.push(0);
    Ok(())
}

fn name(labels: &[&str]) -> Result<Vec<u8>, String> {
    let mut v = Vec::new();
    encode_name(&mut v, labels)?;
    Ok(v)
}

/// TXT rdata: each `key=value` as a length-prefixed string. An empty set is
/// encoded as one empty string, as DNS-SD requires.
pub fn encode_txt(records: &[(String, String)]) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    for (k, v) in records {
        let entry = format!("{k}={v}");
        if entry.len() > 255 {
            return Err(format!("TXT entry {k:?} is longer than 255 bytes"));
        }
        out.push(entry.len() as u8);
        out.extend_from_slice(entry.as_bytes());
    }
    if out.is_empty() {
        out.push(0);
    }
    Ok(out)
}

fn push_u16(out: &mut Vec<u8>, v: u16) {
    out.extend_from_slice(&v.to_be_bytes());
}

fn push_record(
    out: &mut Vec<u8>,
    owner: &[u8],
    rtype: u16,
    class: u16,
    ttl: u32,
    rdata: &[u8],
) -> Result<(), String> {
    if rdata.len() > u16::MAX as usize {
        return Err("record data too long".into());
    }
    out.extend_from_slice(owner);
    push_u16(out, rtype);
    push_u16(out, class);
    out.extend_from_slice(&ttl.to_be_bytes());
    push_u16(out, rdata.len() as u16);
    out.extend_from_slice(rdata);
    Ok(())
}

/// Builds the full unsolicited response: five answers in this order:
/// service PTR, `_services._dns-sd._udp` PTR, SRV, TXT, A.
pub fn announcement_packet(a: &Announcement) -> Result<Vec<u8>, String> {
    let service = name(&[SERVICE_TYPE[0], SERVICE_TYPE[1], DOMAIN])?;
    let meta = name(&[SERVICES_META[0], SERVICES_META[1], SERVICES_META[2], DOMAIN])?;
    let instance = name(&[&a.instance, SERVICE_TYPE[0], SERVICE_TYPE[1], DOMAIN])?;
    let host = name(&[&a.host_label, DOMAIN])?;

    let mut out = Vec::with_capacity(512);
    push_u16(&mut out, 0); // ID: always 0 in mDNS
    push_u16(&mut out, RESPONSE_FLAGS);
    push_u16(&mut out, 0); // questions
    push_u16(&mut out, 5); // answers
    push_u16(&mut out, 0); // authority
    push_u16(&mut out, 0); // additional

    // Shared records: no cache-flush bit.
    push_record(&mut out, &service, TYPE_PTR, CLASS_IN, a.ttl, &instance)?;
    push_record(&mut out, &meta, TYPE_PTR, CLASS_IN, a.ttl, &service)?;

    // Unique records owned by this host: cache-flush bit set.
    let mut srv = Vec::new();
    push_u16(&mut srv, 0); // priority
    push_u16(&mut srv, 0); // weight
    push_u16(&mut srv, a.port);
    srv.extend_from_slice(&host);
    push_record(&mut out, &instance, TYPE_SRV, CLASS_IN | CACHE_FLUSH, a.ttl, &srv)?;
    push_record(
        &mut out,
        &instance,
        TYPE_TXT,
        CLASS_IN | CACHE_FLUSH,
        a.ttl,
        &encode_txt(&a.txt)?,
    )?;
    push_record(&mut out, &host, TYPE_A, CLASS_IN | CACHE_FLUSH, a.ttl, &a.ip.octets())?;
    Ok(out)
}

/// A standard recursive query for the root NS set. Sent to a public resolver
/// only when needed to make a UDP socket pick its outgoing interface.
pub fn root_ns_query() -> Vec<u8> {
    let mut out = Vec::new();
    push_u16(&mut out, 0x5350); // ID
    push_u16(&mut out, 0x0100); // RD
    push_u16(&mut out, 1);
    push_u16(&mut out, 0);
    push_u16(&mut out, 0);
    push_u16(&mut out, 0);
    out.push(0); // root name
    push_u16(&mut out, TYPE_NS);
    push_u16(&mut out, CLASS_IN);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Announcement {
        Announcement {
            instance: "ID".into(),
            host_label: "h".into(),
            port: 49207,
            txt: vec![("name".into(), "AltLoad".into()), ("flags".into(), "1".into())],
            ip: Ipv4Addr::new(192, 168, 1, 20),
            ttl: ANNOUNCE_TTL,
        }
    }

    const SVC: &[u8] = b"\x1c_remotepairing-pairable-host\x04_tcp\x05local\x00";

    #[test]
    fn header_is_unsolicited_authoritative_response() {
        let p = announcement_packet(&sample()).unwrap();
        assert_eq!(&p[..12], &[0, 0, 0x84, 0x00, 0, 0, 0, 5, 0, 0, 0, 0]);
    }

    #[test]
    fn first_record_is_service_ptr() {
        let p = announcement_packet(&sample()).unwrap();
        let mut expect = Vec::new();
        expect.extend_from_slice(SVC); // owner name
        expect.extend_from_slice(&[0x00, 0x0c]); // type PTR
        expect.extend_from_slice(&[0x00, 0x01]); // class IN, no cache flush
        expect.extend_from_slice(&[0x00, 0x00, 0x11, 0x94]); // TTL 4500
        let target = b"\x02ID\x1c_remotepairing-pairable-host\x04_tcp\x05local\x00";
        expect.extend_from_slice(&[0x00, target.len() as u8]); // rdlength
        expect.extend_from_slice(target);
        assert_eq!(&p[12..12 + expect.len()], &expect[..]);
    }

    /// Walks the answer section and returns (owner, type, class, ttl, rdata).
    fn records(p: &[u8]) -> Vec<(Vec<u8>, u16, u16, u32, Vec<u8>)> {
        let count = u16::from_be_bytes([p[6], p[7]]) as usize;
        let mut i = 12;
        let mut out = Vec::new();
        for _ in 0..count {
            let start = i;
            while p[i] != 0 {
                i += 1 + p[i] as usize;
            }
            i += 1;
            let owner = p[start..i].to_vec();
            let rt = u16::from_be_bytes([p[i], p[i + 1]]);
            let cl = u16::from_be_bytes([p[i + 2], p[i + 3]]);
            let ttl = u32::from_be_bytes([p[i + 4], p[i + 5], p[i + 6], p[i + 7]]);
            let len = u16::from_be_bytes([p[i + 8], p[i + 9]]) as usize;
            i += 10;
            out.push((owner, rt, cl, ttl, p[i..i + len].to_vec()));
            i += len;
        }
        assert_eq!(i, p.len(), "no trailing bytes");
        out
    }

    #[test]
    fn all_records_have_expected_layout() {
        let p = announcement_packet(&sample()).unwrap();
        let r = records(&p);
        assert_eq!(r.len(), 5);

        assert_eq!(r[1].0, b"\x09_services\x07_dns-sd\x04_udp\x05local\x00".to_vec());
        assert_eq!((r[1].1, r[1].2), (TYPE_PTR, 0x0001));
        assert_eq!(r[1].4, SVC.to_vec());

        // SRV: priority 0, weight 0, port 49207 (0xC037), target h.local
        assert_eq!((r[2].1, r[2].2, r[2].3), (TYPE_SRV, 0x8001, 4500));
        assert_eq!(r[2].4, b"\x00\x00\x00\x00\xc0\x37\x01h\x05local\x00".to_vec());

        assert_eq!((r[3].1, r[3].2), (TYPE_TXT, 0x8001));
        assert_eq!(r[3].4, b"\x0cname=AltLoad\x07flags=1".to_vec());

        assert_eq!(r[4].0, b"\x01h\x05local\x00".to_vec());
        assert_eq!((r[4].1, r[4].2, r[4].3), (TYPE_A, 0x8001, 4500));
        assert_eq!(r[4].4, vec![192, 168, 1, 20]);
    }

    #[test]
    fn goodbye_uses_zero_ttl() {
        let mut a = sample();
        a.ttl = 0;
        let p = announcement_packet(&a).unwrap();
        assert!(records(&p).iter().all(|r| r.3 == 0));
    }

    #[test]
    fn txt_encoding() {
        assert_eq!(encode_txt(&[]).unwrap(), vec![0]);
        let t = encode_txt(&[("a".into(), "".into()), ("ver".into(), "26".into())]).unwrap();
        assert_eq!(t, b"\x02a=\x06ver=26".to_vec());
        assert!(encode_txt(&[("k".into(), "x".repeat(254))]).is_err());
        assert!(encode_txt(&[("k".into(), "x".repeat(253))]).is_ok());
    }

    #[test]
    fn rejects_bad_labels() {
        let mut v = Vec::new();
        assert!(encode_name(&mut v, &[""]).is_err());
        assert!(encode_name(&mut v, &[&"a".repeat(64)]).is_err());
        // A 36-character UUID instance label is fine.
        assert!(encode_name(&mut v, &["9f0b6d0e-3c1a-3f4e-8a7b-2c9d1e0f3a4b"]).is_ok());
    }

    #[test]
    fn root_query_layout() {
        assert_eq!(
            root_ns_query(),
            vec![0x53, 0x50, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 1]
        );
    }
}
