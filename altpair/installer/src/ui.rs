// Output for a narrow phone terminal: lines of at most 45 columns.

use std::io::Write;

pub const WIDTH: usize = 45;

/// Cuts a line to `width` characters, ending it with "…" when cut.
pub fn fit(s: &str, width: usize) -> String {
    if s.chars().count() <= width {
        return s.to_string();
    }
    let mut out: String = s.chars().take(width.saturating_sub(1)).collect();
    out.push('…');
    out
}

/// Word-wraps text to `width` columns, keeping existing line breaks. Words longer
/// than a line are split.
pub fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut lines = Vec::new();
    for para in text.lines() {
        let mut line = String::new();
        for word in para.split_whitespace() {
            let mut word: Vec<char> = word.chars().collect();
            while word.len() > width {
                if !line.is_empty() {
                    lines.push(std::mem::take(&mut line));
                }
                lines.push(word.drain(..width).collect());
            }
            let word: String = word.into_iter().collect();
            if word.is_empty() {
                continue;
            }
            let needed = line.chars().count() + usize::from(!line.is_empty()) + word.chars().count();
            if needed > width && !line.is_empty() {
                lines.push(std::mem::take(&mut line));
            }
            if !line.is_empty() {
                line.push(' ');
            }
            line.push_str(&word);
        }
        lines.push(line);
    }
    lines
}

pub fn print_wrapped(text: &str) {
    for line in wrap(text, WIDTH) {
        println!("{line}");
    }
}

/// Wrapped text indented under a step.
pub fn note(text: &str) {
    for line in wrap(text, WIDTH - 6) {
        println!("      {line}");
    }
}

pub fn eprint_wrapped(text: &str) {
    for line in wrap(text, WIDTH) {
        eprintln!("{line}");
    }
}

/// "[n/4] what" at the start of a step.
pub fn step(n: u32, what: &str) {
    println!("{}", fit(&format!("[{n}/4] {what}"), WIDTH));
}

/// The indented result line that ends a step.
pub fn result(what: &str) {
    println!("{}", fit(&format!("      {what}"), WIDTH));
}

/// Shows stages from the core. Each stage is printed once. On a terminal a
/// known fraction is shown as a percent on the same line, rewritten in place;
/// otherwise only the stage names are printed.
pub struct Progress {
    tty: bool,
    stage: Option<String>,
    percent: Option<u32>,
    line_open: bool,
}

impl Progress {
    pub fn new(tty: bool) -> Self {
        Self { tty, stage: None, percent: None, line_open: false }
    }

    /// Returns what to write for this update (often nothing).
    pub fn update(&mut self, stage: &str, fraction: f64) -> String {
        let mut out = String::new();
        let label = fit(&format!("      {}", stage.trim()), WIDTH - 5);
        if self.stage.as_deref() != Some(stage) {
            out.push_str(&self.finish());
            self.stage = Some(stage.to_string());
            self.percent = None;
            if !self.tty {
                out.push_str(&label);
                out.push('\n');
                return out;
            }
            out.push_str(&label);
            self.line_open = true;
        }
        if self.tty && fraction >= 0.0 {
            let pct = (fraction.clamp(0.0, 1.0) * 100.0).floor() as u32;
            if self.percent != Some(pct) {
                self.percent = Some(pct);
                out.push_str(&format!("\r\x1b[K{label} {pct:>3}%"));
                self.line_open = true;
            }
        }
        out
    }

    /// Ends an open progress line.
    pub fn finish(&mut self) -> String {
        if self.line_open {
            self.line_open = false;
            "\n".into()
        } else {
            String::new()
        }
    }

    pub fn write(&mut self, stage: &str, fraction: f64) {
        let s = self.update(stage, fraction);
        if !s.is_empty() {
            print!("{s}");
            let _ = std::io::stdout().flush();
        }
    }

    pub fn close(&mut self) {
        let s = self.finish();
        if !s.is_empty() {
            print!("{s}");
            let _ = std::io::stdout().flush();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fit_and_wrap() {
        assert_eq!(fit("short", 10), "short");
        assert_eq!(fit("0123456789abc", 10), "012345678…");
        let text = "Trust your Apple ID in Settings › General › VPN & Device Management, then open AltLoad.";
        let lines = wrap(text, WIDTH);
        assert!(lines.len() >= 2);
        assert!(lines.iter().all(|l| l.chars().count() <= WIDTH));
        assert_eq!(lines.join(" "), text);
        assert_eq!(wrap("a\n\nb", 10), vec!["a", "", "b"]);
        assert_eq!(wrap("abcdefghij", 4), vec!["abcd", "efgh", "ij"]);
    }

    #[test]
    fn plain_output_prints_each_stage_once() {
        let mut p = Progress::new(false);
        assert_eq!(p.update("Signing…", 0.0), "      Signing…\n");
        assert_eq!(p.update("Signing…", 0.5), "");
        assert_eq!(p.update("Installing…", -1.0), "      Installing…\n");
        assert_eq!(p.finish(), "");
    }

    #[test]
    fn terminal_output_rewrites_the_percent() {
        let mut p = Progress::new(true);
        let first = p.update("Signing…", 0.0);
        assert!(first.starts_with("      Signing…"));
        assert!(first.ends_with("  0%"));
        assert_eq!(p.update("Signing…", 0.001), "");
        assert!(p.update("Signing…", 0.5).ends_with(" 50%"));
        let next = p.update("Installing…", -1.0);
        assert!(next.starts_with('\n'));
        assert_eq!(p.finish(), "\n");
    }
}
