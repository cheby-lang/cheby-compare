//! spawn_many: spawn `n` short tasks in batches of `BATCH`, join each batch and print the sum.
//! Each task is one tokio task on the default multi-threaded runtime.

use std::env;

const BATCH: u64 = 1_000;
const ROUNDS: u32 = 10;
const MODULUS: u64 = 2_147_483_647;
const MULTIPLIER: u64 = 48_271;

/// The value of the task with this index: `ROUNDS` steps of the MINSTD generator from `index + 1`.
fn work(index: u64) -> u64 {
    let mut x = index + 1;
    for _ in 0..ROUNDS {
        x = x * MULTIPLIER % MODULUS;
    }
    x
}

/// Spawns one task per index in `start..start + count`, awaits them all and returns their sum.
async fn spawn_and_join(start: u64, count: u64) -> u64 {
    let handles: Vec<_> = (start..start + count)
        .map(|index| tokio::spawn(async move { work(index) }))
        .collect();
    let mut sum = 0;
    for handle in handles {
        sum += handle.await.expect("task panicked");
    }
    sum
}

#[tokio::main]
async fn main() {
    let n: u64 = env::args()
        .nth(1)
        .expect("usage: main <n>")
        .parse()
        .expect("n must be a non-negative integer");
    let mut sum = 0;
    let mut start = 0;
    while start < n {
        sum += spawn_and_join(start, BATCH.min(n - start)).await;
        start += BATCH;
    }
    println!("tasks: {n}");
    println!("sum: {sum}");
}
