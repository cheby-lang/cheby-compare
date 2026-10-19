//! word_freq: counts the words of a file and prints the 20 most frequent.

use std::collections::HashMap;
use std::io::{self, BufWriter, Write};

const TOP: usize = 20;

fn main() -> io::Result<()> {
    let path = std::env::args().nth(1).expect("usage: main FILE");
    let text = std::fs::read_to_string(path)?;

    let mut counts: HashMap<&str, u64> = HashMap::new();
    let mut total: u64 = 0;
    for word in text.split_ascii_whitespace() {
        *counts.entry(word).or_insert(0) += 1;
        total += 1;
    }

    let mut ranked: Vec<(&str, u64)> = counts.into_iter().collect();
    let distinct = ranked.len();
    ranked.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(b.0)));

    let mut out = BufWriter::new(io::stdout().lock());
    writeln!(out, "total {total}")?;
    writeln!(out, "distinct {distinct}")?;
    for (word, count) in ranked.iter().take(TOP) {
        writeln!(out, "{count} {word}")?;
    }
    out.flush()
}
