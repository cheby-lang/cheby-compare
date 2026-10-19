//! json_roundtrip: parses a JSON array of records, transforms it and serializes it again.

use serde::{Deserialize, Serialize};
use std::{env, fs};

const FNV_OFFSET: u32 = 2_166_136_261;
const FNV_PRIME: u32 = 16_777_619;

#[derive(Deserialize, Serialize)]
struct Address {
    street: String,
    city: String,
    zip: i64,
}

#[derive(Deserialize, Serialize)]
struct Entry {
    day: i64,
    amount: i64,
}

#[derive(Deserialize)]
struct Record {
    id: i64,
    name: String,
    active: bool,
    score: i64,
    tags: Vec<String>,
    address: Address,
    history: Vec<Entry>,
}

/// A kept record as it is written: `active` is gone, `score` changed and `total` added.
#[derive(Serialize)]
struct Output<'a> {
    id: i64,
    name: &'a str,
    score: i64,
    tags: &'a [String],
    address: &'a Address,
    history: &'a [Entry],
    total: i64,
}

fn fnv1a(hash: u32, data: &[u8]) -> u32 {
    data.iter()
        .fold(hash, |h, &b| (h ^ u32::from(b)).wrapping_mul(FNV_PRIME))
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let text = fs::read_to_string(&args[1]).expect("cannot read the input file");
    let reps: u64 = args[2]
        .parse()
        .expect("reps must be a non-negative integer");

    let (mut records_n, mut active_n, mut score_sum, mut tags_n) = (0i64, 0i64, 0i64, 0i64);
    let (mut history_n, mut amount_sum, mut output_bytes) = (0i64, 0i64, 0i64);
    let mut hash = FNV_OFFSET;
    for rep in 0..reps {
        let records: Vec<Record> = serde_json::from_str(&text).expect("invalid input");
        let mut kept = Vec::new();
        for r in &records {
            let total: i64 = r.history.iter().map(|e| e.amount).sum();
            records_n += 1;
            score_sum += r.score;
            tags_n += r.tags.len() as i64;
            history_n += r.history.len() as i64;
            amount_sum += total;
            if r.active {
                active_n += 1;
                kept.push(Output {
                    id: r.id,
                    name: &r.name,
                    score: r.score + 100 * r.tags.len() as i64,
                    tags: &r.tags,
                    address: &r.address,
                    history: &r.history,
                    total,
                });
            }
        }
        let out = serde_json::to_vec(&kept).expect("serialization cannot fail");
        output_bytes += out.len() as i64;
        if rep == reps - 1 {
            hash = fnv1a(FNV_OFFSET, &out);
        }
    }

    println!("records {records_n}");
    println!("active {active_n}");
    println!("score_sum {score_sum}");
    println!("tags {tags_n}");
    println!("history {history_n}");
    println!("amount_sum {amount_sum}");
    println!("output_bytes {output_bytes}");
    println!("output_fnv1a {hash}");
}
