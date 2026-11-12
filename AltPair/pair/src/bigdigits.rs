//! Draws digits five rows tall with `#`, so the pairing PIN is easy to read.
//! Six digits come to 35 columns.

const FONT: [[&str; 5]; 10] = [
    ["#####", "#   #", "#   #", "#   #", "#####"],
    ["  #  ", " ##  ", "  #  ", "  #  ", " ### "],
    ["#####", "    #", "#####", "#    ", "#####"],
    ["#####", "    #", " ####", "    #", "#####"],
    ["#   #", "#   #", "#####", "    #", "    #"],
    ["#####", "#    ", "#####", "    #", "#####"],
    ["#####", "#    ", "#####", "#   #", "#####"],
    ["#####", "    #", "   # ", "  #  ", "  #  "],
    ["#####", "#   #", "#####", "#   #", "#####"],
    ["#####", "#   #", "#####", "    #", "#####"],
];

/// Five lines of large digits. Characters other than 0-9 are drawn as blanks.
pub fn render(digits: &str) -> Vec<String> {
    (0..5)
        .map(|row| {
            digits
                .chars()
                .map(|c| match c.to_digit(10) {
                    Some(d) => FONT[d as usize][row],
                    None => "     ",
                })
                .collect::<Vec<_>>()
                .join(" ")
                .trim_end()
                .to_string()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn six_digits_fit_40_columns() {
        let rows = render("123456");
        assert_eq!(rows.len(), 5);
        assert!(rows.iter().all(|r| r.chars().count() <= 40));
        assert_eq!(rows[0].chars().count(), 35);
    }

    #[test]
    fn renders_zero_and_one() {
        assert_eq!(render("10")[0], "  #   #####");
        assert_eq!(render("10")[1], " ##   #   #");
    }
}
