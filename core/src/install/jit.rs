// The debugger side of an app's JIT requests.
//
// Being attached once is enough for most apps: the process counts as debugged and
// may map executable memory. On devices where iOS checks each executable page,
// that isn't enough, so emulators ask the attached debugger for help by stopping
// on a `brk` instruction with a request in their registers:
//
//   brk #0xf00d, x16 = 0                      detach: the app is done asking
//   brk #0xf00d, x16 = 1, x0 = addr, x1 = len make [addr, addr+len) usable for JIT;
//                                             with addr 0, allocate it first and
//                                             return the address in x0
//   brk #0x69,   x0 = addr, x1 = len          the older form of the same request,
//                                             answered once, then detach
//
// A region is made usable by writing one byte into each 16 KiB page through
// debugserver. Requests this file doesn't know (x16 = 2 sends a script to run)
// are skipped: the app continues past the `brk` with its registers unchanged.

use std::time::Duration;

use idevice::debug_proxy::{DebugProxyClient, DebugserverCommand};
use idevice::ReadWrite;

use super::{err, Callbacks};

const PAGE: u64 = 16_384;
/// Packets sent before their replies are read, so a large region isn't one round
/// trip per page.
const BATCH: usize = 128;
/// How long an app gets to make its first request before it's treated as one
/// that only needed the attach.
const FIRST_REQUEST: Duration = Duration::from_secs(8);
/// How long to stay attached to an app that has made requests and gone quiet
/// without detaching.
const IDLE: Duration = Duration::from_secs(300);
/// A region larger than this is refused rather than written page by page.
const MAX_REGION: u64 = 16 << 30;

const SIGSTOP: u8 = 17;

/// Which requests an app makes. Apps written for the older form expect the
/// debugger to leave after the first one.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(super) enum Dialect {
    Universal,
    Legacy,
}

impl Dialect {
    pub(super) fn named(name: &str) -> Dialect {
        if name == "legacy" { Dialect::Legacy } else { Dialect::Universal }
    }
}

/// How a session ended.
#[derive(Debug, PartialEq, Eq)]
pub(super) struct Served {
    /// JIT requests answered.
    pub requests: u32,
    /// "app" (it asked to detach), "quiet" (no more requests came) or "exited".
    pub ended: &'static str,
}

/// A thread stopped, as debugserver reports it: `T05thread:1a2b;00:…;01:…;`.
#[derive(Debug, PartialEq, Eq)]
struct Stop {
    signal: u8,
    thread: String,
    x0: Option<u64>,
    x1: Option<u64>,
    x16: Option<u64>,
    pc: Option<u64>,
}

fn parse_stop(reply: &str) -> Option<Stop> {
    let rest = reply.strip_prefix('T')?;
    let signal = u8::from_str_radix(rest.get(..2)?, 16).ok()?;
    let mut stop = Stop { signal, thread: String::new(), x0: None, x1: None, x16: None, pc: None };
    for pair in rest.get(2..)?.split(';') {
        let Some((key, value)) = pair.split_once(':') else { continue };
        match key {
            "thread" => stop.thread = value.to_string(),
            // Register numbers are hex: 0x10 is x16 and 0x20 is pc.
            "00" => stop.x0 = register(value),
            "01" => stop.x1 = register(value),
            "10" => stop.x16 = register(value),
            "20" => stop.pc = register(value),
            _ => {}
        }
    }
    if stop.thread.is_empty() { None } else { Some(stop) }
}

/// A 64-bit register as debugserver sends it: 16 hex digits, least significant byte first.
fn register(hex: &str) -> Option<u64> {
    if hex.len() != 16 {
        return None;
    }
    let mut bytes = [0u8; 8];
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = u8::from_str_radix(hex.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(u64::from_le_bytes(bytes))
}

fn register_hex(value: u64) -> String {
    value.to_le_bytes().iter().map(|b| format!("{b:02x}")).collect()
}

/// The immediate of an AArch64 `brk`, from the four bytes at pc as `m` returns
/// them. None for any other instruction.
fn brk_immediate(memory_hex: &str) -> Option<u16> {
    let word = u32::from_le_bytes(register_bytes4(memory_hex)?);
    if word & 0xFFE0_001F != 0xD420_0000 {
        return None;
    }
    Some(((word >> 5) & 0xFFFF) as u16)
}

fn register_bytes4(hex: &str) -> Option<[u8; 4]> {
    if hex.len() != 8 {
        return None;
    }
    let mut bytes = [0u8; 4];
    for (i, byte) in bytes.iter_mut().enumerate() {
        *byte = u8::from_str_radix(hex.get(i * 2..i * 2 + 2)?, 16).ok()?;
    }
    Some(bytes)
}

fn packet(data: &str) -> Vec<u8> {
    let sum = data.bytes().fold(0u8, |acc, b| acc.wrapping_add(b));
    format!("${data}#{sum:02x}").into_bytes()
}

fn pages(len: u64) -> u64 {
    if len == 0 { 0 } else { (len - 1) / PAGE + 1 }
}

/// What to do about a stop, decided from the registers and the instruction alone.
#[derive(Debug, PartialEq, Eq)]
enum Action {
    /// Step over the `brk` and detach.
    Detach,
    /// Make the region usable; `allocate` first when the app passed no address.
    Prepare { address: u64, len: u64, allocate: bool, then_detach: bool },
    /// Step over the `brk` and put this in x0.
    Answer(u64),
    /// Step over the `brk` and carry on.
    Skip,
    /// Not a request: hand the signal back to the app.
    PassSignal,
}

fn decide(stop: &Stop, immediate: Option<u16>, dialect: Dialect) -> Action {
    let (x0, x1) = (stop.x0.unwrap_or(0), stop.x1.unwrap_or(0));
    match immediate {
        Some(0xf00d) => match stop.x16 {
            Some(0) => Action::Detach,
            Some(1) if x0 == 0 && x1 == 0 => Action::Skip,
            Some(1) => Action::Prepare { address: x0, len: x1, allocate: x0 == 0, then_detach: false },
            _ => Action::Skip,
        },
        Some(0x69) if dialect == Dialect::Legacy => {
            Action::Prepare { address: x0, len: x1, allocate: false, then_detach: true }
        }
        // An app written for the older form, run without it: it reads this as "not supported".
        Some(0x69) => Action::Answer(0xE000_0069),
        Some(0x68) => Action::Skip,
        _ => Action::PassSignal,
    }
}

async fn command<R: ReadWrite>(debug: &mut DebugProxyClient<R>, text: String, what: &str) -> Result<String, String> {
    debug
        .send_command(DebugserverCommand::new(text, Vec::new()))
        .await
        .map(Option::unwrap_or_default)
        .map_err(|e| err(what, e))
}

/// Writes one byte into every page of the region, in batches.
async fn prepare<R: ReadWrite>(debug: &mut DebugProxyClient<R>, address: u64, len: u64) -> Result<(), String> {
    let count = pages(len);
    let mut next = 0u64;
    while next < count {
        let batch = (count - next).min(BATCH as u64);
        let mut bytes = Vec::with_capacity(batch as usize * 24);
        for i in 0..batch {
            bytes.extend_from_slice(&packet(&format!("M{:x},1:69", address + (next + i) * PAGE)));
        }
        debug.send_raw(&bytes).await.map_err(|e| err("Couldn't write to the app's JIT region", e))?;
        for _ in 0..batch {
            let reply = debug
                .read_response()
                .await
                .map_err(|e| err("Couldn't write to the app's JIT region", e))?
                .unwrap_or_default();
            if reply.starts_with('E') {
                return Err(format!("debugserver couldn't write to the app's JIT region ({reply})."));
            }
        }
        next += batch;
    }
    Ok(())
}

/// Stops the running app, then detaches. Used when no more requests are coming.
async fn interrupt_and_detach<R: ReadWrite>(debug: &mut DebugProxyClient<R>) -> Result<(), String> {
    debug.send_raw(&[0x03]).await.map_err(|e| err("Couldn't pause the app to detach", e))?;
    // The stop this causes; if the app exited in the meantime there's nothing to detach from.
    let _ = tokio::time::timeout(Duration::from_secs(5), debug.read_response()).await;
    command(debug, "D".to_string(), "Couldn't detach from the app").await.map(drop)
}

/// Runs the session for an app that is attached and stopped: lets it run, answers
/// its JIT requests, and returns once it detaches, exits or goes quiet.
pub(super) async fn serve<R: ReadWrite>(
    debug: &mut DebugProxyClient<R>,
    dialect: Dialect,
    cbs: Callbacks,
) -> Result<Served, String> {
    // Without acknowledgements a reply is one packet, so waiting for a stop can
    // time out without leaving half an exchange behind.
    let reply = command(debug, "QStartNoAckMode".to_string(), "Couldn't set up debugserver").await?;
    if reply == "OK" {
        debug.set_ack_mode(false);
    }

    let mut requests = 0u32;
    let mut resume = "c".to_string();
    loop {
        debug
            .send_raw(&packet(&resume))
            .await
            .map_err(|e| err("Couldn't let the app run", e))?;
        resume = "c".to_string();

        let wait = if requests == 0 { FIRST_REQUEST } else { IDLE };
        let reply = match tokio::time::timeout(wait, debug.read_response()).await {
            Ok(reply) => reply.map_err(|e| err("Lost the debugger connection", e))?.unwrap_or_default(),
            Err(_) => {
                interrupt_and_detach(debug).await?;
                return Ok(Served { requests, ended: "quiet" });
            }
        };
        if reply.starts_with('W') || reply.starts_with('X') {
            return Ok(Served { requests, ended: "exited" });
        }
        let Some(stop) = parse_stop(&reply) else { continue };
        let Some(pc) = stop.pc else { continue };

        let instruction = command(debug, format!("m{pc:x},4"), "Couldn't read the app's request").await?;
        let action = decide(&stop, brk_immediate(&instruction), dialect);
        if action == Action::PassSignal {
            // Not a request: the app gets its signal, as it would without a debugger.
            // A stop signal is dropped instead, since passing it on would suspend the app.
            if stop.signal != SIGSTOP {
                resume = format!("vCont;S{:02x}:{}", stop.signal, stop.thread);
            }
            continue;
        }

        // Every request resumes after its `brk`.
        let thread = &stop.thread;
        command(debug, format!("P20={};thread:{thread};", register_hex(pc + 4)), "Couldn't step over the app's request").await?;

        match action {
            Action::Detach => {
                command(debug, "D".to_string(), "Couldn't detach from the app").await?;
                return Ok(Served { requests, ended: "app" });
            }
            Action::Prepare { address, len, allocate, then_detach } => {
                if len > MAX_REGION {
                    return Err(format!("The app asked for a {len}-byte JIT region, which is more than AltLoad prepares."));
                }
                cbs.progress("Preparing the app's JIT memory…", -1.0);
                let mut address = address;
                if allocate {
                    let reply = command(debug, format!("_M{len:x},rx"), "Couldn't allocate JIT memory").await?;
                    address = u64::from_str_radix(&reply, 16)
                        .map_err(|_| format!("debugserver couldn't allocate JIT memory ({reply})."))?;
                }
                prepare(debug, address, len).await?;
                if !then_detach {
                    command(debug, format!("P0={};thread:{thread};", register_hex(address)), "Couldn't answer the app's request").await?;
                }
                requests += 1;
                if then_detach {
                    command(debug, "D".to_string(), "Couldn't detach from the app").await?;
                    return Ok(Served { requests, ended: "app" });
                }
            }
            Action::Answer(value) => {
                command(debug, format!("P0={};thread:{thread};", register_hex(value)), "Couldn't answer the app's request").await?;
            }
            Action::Skip | Action::PassSignal => {}
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stop(x0: u64, x1: u64, x16: u64) -> Stop {
        Stop { signal: 5, thread: "1a2b".into(), x0: Some(x0), x1: Some(x1), x16: Some(x16), pc: Some(0x1_0000_4000) }
    }

    #[test]
    fn a_stop_reply_gives_the_thread_and_registers() {
        let reply = format!(
            "T05thread:1a2b;00:{};01:{};10:{};20:{};metype:6;",
            register_hex(0x2_8000_0000),
            register_hex(0x4000),
            register_hex(1),
            register_hex(0x1_0000_4000)
        );
        let parsed = parse_stop(&reply).unwrap();
        assert_eq!(parsed, Stop { signal: 5, ..stop(0x2_8000_0000, 0x4000, 1) });
        assert!(parse_stop("W00").is_none());
        assert!(parse_stop("T05metype:6;").is_none());
    }

    #[test]
    fn registers_are_little_endian() {
        assert_eq!(register("0040000001000000"), Some(0x1_0000_4000));
        assert_eq!(register_hex(0x1_0000_4004), "0440000001000000");
        assert_eq!(register("00"), None);
    }

    #[test]
    fn only_a_brk_has_an_immediate() {
        // brk #0xf00d is 0xd43e01a0, brk #0x69 is 0xd4200d20; `m` returns the bytes in memory order.
        assert_eq!(brk_immediate("a0013ed4"), Some(0xf00d));
        assert_eq!(brk_immediate("200d20d4"), Some(0x69));
        // ret
        assert_eq!(brk_immediate("c0035fd6"), None);
        assert_eq!(brk_immediate("E08"), None);
    }

    #[test]
    fn packets_carry_their_checksum() {
        assert_eq!(packet("c"), b"$c#63");
        assert_eq!(packet("D"), b"$D#44");
    }

    #[test]
    fn a_region_is_counted_in_whole_pages() {
        assert_eq!(pages(0), 0);
        assert_eq!(pages(1), 1);
        assert_eq!(pages(PAGE), 1);
        assert_eq!(pages(PAGE + 1), 2);
    }

    #[test]
    fn requests_are_told_apart() {
        let universal = Dialect::Universal;
        assert_eq!(decide(&stop(0, 0, 0), Some(0xf00d), universal), Action::Detach);
        assert_eq!(
            decide(&stop(0x8000, 0x4000, 1), Some(0xf00d), universal),
            Action::Prepare { address: 0x8000, len: 0x4000, allocate: false, then_detach: false }
        );
        assert_eq!(
            decide(&stop(0, 0x4000, 1), Some(0xf00d), universal),
            Action::Prepare { address: 0, len: 0x4000, allocate: true, then_detach: false }
        );
        assert_eq!(decide(&stop(0, 0, 1), Some(0xf00d), universal), Action::Skip);
        assert_eq!(decide(&stop(1, 2, 2), Some(0xf00d), universal), Action::Skip);
        assert_eq!(decide(&stop(1, 2, 0), Some(0x69), universal), Action::Answer(0xE000_0069));
        assert_eq!(
            decide(&stop(0x8000, 0x4000, 0), Some(0x69), Dialect::Legacy),
            Action::Prepare { address: 0x8000, len: 0x4000, allocate: false, then_detach: true }
        );
        assert_eq!(decide(&stop(0, 0, 0), Some(0x1), universal), Action::PassSignal);
        assert_eq!(decide(&stop(0, 0, 0), None, universal), Action::PassSignal);
    }
}
