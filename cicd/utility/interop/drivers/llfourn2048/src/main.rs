//! Batch adapter over LLFourn's base2048 crate, matching the line protocol the
//! node adapter speaks:
//!
//!   llfourn2048 encode   stdin is one lowercase hex string per line, stdout is
//!                        the encoded text, one line per input.
//!   llfourn2048 decode   the reverse. A line the reference refuses comes back
//!                        as "!error", so a rejection shows up as a mismatch
//!                        rather than a panic.
//!
//! Copyright © 2026 Bubbles (ID: XଌฅრX۳ᛟԃლፀƅꓩหδლც)
//! Licensed under GNU GPL v2 <https://www.gnu.org/licenses/gpl-2.0.html>. No warranty.
//! SPDX-License-Identifier: GPL-2.0-or-later

use std::io::{self, Read, Write};

fn hex_to_bytes(hex: &str) -> Option<Vec<u8>> {
    // is_ascii keeps the byte slicing below on char boundaries.
    if hex.len() % 2 != 0 || !hex.is_ascii() {
        return None;
    }
    (0..hex.len() / 2)
        .map(|i| u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).ok())
        .collect()
}

fn bytes_to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn main() {
    let mode = std::env::args().nth(1).unwrap_or_default();
    if mode != "encode" && mode != "decode" {
        eprintln!("usage: llfourn2048 <encode|decode>");
        std::process::exit(2);
    }

    let mut input = String::new();
    io::stdin().read_to_string(&mut input).expect("read stdin");
    // A trailing newline would otherwise read as one extra empty sample.
    let body = input.strip_suffix('\n').unwrap_or(&input);

    let stdout = io::stdout();
    let mut out = io::BufWriter::new(stdout.lock());
    if !input.is_empty() {
        for line in body.split('\n') {
            let result = if mode == "encode" {
                hex_to_bytes(line).map(|bytes| base2048::encode(&bytes))
            } else {
                base2048::decode(line).map(|bytes| bytes_to_hex(&bytes))
            };
            writeln!(out, "{}", result.unwrap_or_else(|| "!error".to_string())).expect("write");
        }
    }
    out.flush().expect("flush");
}
