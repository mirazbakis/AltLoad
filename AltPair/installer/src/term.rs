// Terminal input: plain lines, passwords with echo off, and restoring the
// terminal on every way out (normal return, panic unwind, Ctrl-C, SIGTERM, SIGHUP).

use std::cell::UnsafeCell;
use std::io::{self, BufRead, Write};
use std::mem::MaybeUninit;
use std::sync::atomic::{AtomicBool, Ordering};

/// The terminal settings to put back. Written only while `SAVED` is false and
/// read by the signal handler only while it is true.
struct SavedTermios(UnsafeCell<MaybeUninit<libc::termios>>);
unsafe impl Sync for SavedTermios {}

static TERMIOS: SavedTermios = SavedTermios(UnsafeCell::new(MaybeUninit::uninit()));
static SAVED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_signal(sig: libc::c_int) {
    // Only async-signal-safe calls here.
    unsafe {
        if SAVED.load(Ordering::SeqCst) {
            libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, (*TERMIOS.0.get()).as_ptr());
        }
        let nl = b"\n";
        libc::write(libc::STDERR_FILENO, nl.as_ptr().cast(), nl.len());
        libc::_exit(128 + sig);
    }
}

/// Installs handlers that restore the terminal before exiting on Ctrl-C and friends.
pub fn install_signal_handlers() {
    let handler = on_signal as extern "C" fn(libc::c_int) as libc::sighandler_t;
    for sig in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP] {
        unsafe {
            libc::signal(sig, handler);
        }
    }
}

pub fn is_tty(fd: libc::c_int) -> bool {
    unsafe { libc::isatty(fd) == 1 }
}

/// Prints the prompt and reads one line from stdin, without the line ending.
/// Returns None at end of input.
pub fn read_line(prompt: &str) -> io::Result<Option<String>> {
    print!("{prompt}");
    io::stdout().flush()?;
    let mut line = String::new();
    if io::stdin().lock().read_line(&mut line)? == 0 {
        return Ok(None);
    }
    let trimmed = line.trim_end_matches(['\r', '\n']).len();
    line.truncate(trimmed);
    Ok(Some(line))
}

/// Echo is off while this is alive; dropping it puts the terminal back.
struct EchoOff;

impl EchoOff {
    fn new() -> io::Result<Self> {
        unsafe {
            let mut current = MaybeUninit::<libc::termios>::uninit();
            if libc::tcgetattr(libc::STDIN_FILENO, current.as_mut_ptr()) != 0 {
                return Err(io::Error::last_os_error());
            }
            (*TERMIOS.0.get()).write(current.assume_init());
            SAVED.store(true, Ordering::SeqCst);

            let mut quiet = current.assume_init();
            quiet.c_lflag &= !libc::ECHO;
            quiet.c_lflag |= libc::ECHONL;
            if libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, &quiet) != 0 {
                SAVED.store(false, Ordering::SeqCst);
                return Err(io::Error::last_os_error());
            }
        }
        Ok(Self)
    }
}

impl Drop for EchoOff {
    fn drop(&mut self) {
        unsafe {
            libc::tcsetattr(libc::STDIN_FILENO, libc::TCSANOW, (*TERMIOS.0.get()).as_ptr());
        }
        SAVED.store(false, Ordering::SeqCst);
    }
}

/// Reads a line with echo off when stdin is a terminal, or as-is when it is not.
pub fn read_secret(prompt: &str) -> io::Result<Option<String>> {
    if !is_tty(libc::STDIN_FILENO) {
        return read_line(prompt);
    }
    let _quiet = EchoOff::new()?;
    read_line(prompt)
}

/// Overwrites a string's bytes before it is dropped.
pub fn wipe(s: &mut String) {
    // Zero bytes are valid UTF-8, so the String stays valid.
    unsafe { s.as_bytes_mut() }.fill(0);
    s.clear();
}
