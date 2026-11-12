//! Adds the iPhone's UDID to a pairing plist so the receiving app does not
//! have to ask for it.

/// Returns the plist as XML with a `UDID` key set to `udid` when the plist has
/// no `UDID` or an empty one. An existing non-empty `UDID` is kept. With an
/// empty `udid` the plist is only re-serialized.
pub fn with_udid(plist_bytes: &[u8], udid: &str) -> Result<Vec<u8>, String> {
    let mut dict: plist::Dictionary =
        plist::from_bytes(plist_bytes).map_err(|e| format!("bad pairing plist: {e}"))?;
    let has = matches!(dict.get("UDID"), Some(plist::Value::String(s)) if !s.is_empty());
    if !has && !udid.is_empty() {
        dict.insert("UDID".into(), plist::Value::String(udid.to_string()));
    }
    let mut out = Vec::new();
    plist::to_writer_xml(&mut out, &dict).map_err(|e| format!("cannot write plist: {e}"))?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dict(bytes: &[u8]) -> plist::Dictionary {
        plist::from_bytes(bytes).unwrap()
    }

    fn sample(extra: Option<(&str, &str)>) -> Vec<u8> {
        let mut d = plist::Dictionary::new();
        d.insert("identifier".into(), plist::Value::String("abc".into()));
        d.insert("public_key".into(), plist::Value::Data(vec![1; 32]));
        if let Some((k, v)) = extra {
            d.insert(k.into(), plist::Value::String(v.into()));
        }
        let mut out = Vec::new();
        plist::to_writer_xml(&mut out, &d).unwrap();
        out
    }

    #[test]
    fn inserts_missing_udid() {
        let out = with_udid(&sample(None), "00008140-001234").unwrap();
        let d = dict(&out);
        assert_eq!(d.get("UDID").and_then(|v| v.as_string()), Some("00008140-001234"));
        assert_eq!(d.get("identifier").and_then(|v| v.as_string()), Some("abc"));
        assert_eq!(d.get("public_key").and_then(|v| v.as_data()), Some(&[1u8; 32][..]));
    }

    #[test]
    fn replaces_empty_udid() {
        let out = with_udid(&sample(Some(("UDID", ""))), "X").unwrap();
        assert_eq!(dict(&out).get("UDID").and_then(|v| v.as_string()), Some("X"));
    }

    #[test]
    fn keeps_existing_udid() {
        let out = with_udid(&sample(Some(("UDID", "OLD"))), "NEW").unwrap();
        assert_eq!(dict(&out).get("UDID").and_then(|v| v.as_string()), Some("OLD"));
    }

    #[test]
    fn empty_udid_adds_nothing() {
        let out = with_udid(&sample(None), "").unwrap();
        assert!(dict(&out).get("UDID").is_none());
    }

    #[test]
    fn rejects_garbage() {
        assert!(with_udid(b"not a plist", "X").is_err());
    }
}
