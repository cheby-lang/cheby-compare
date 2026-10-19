//! prime_sieve: the concurrent prime sieve, one tokio task per stage, connected by one-slot
//! channels.

use std::env;
use tokio::sync::mpsc::{Receiver, Sender, channel};

/// Sends 2, 3, 4 and so on until the receiving end goes away.
async fn generate(output: Sender<i64>) {
    let mut n = 2;
    while output.send(n).await.is_ok() {
        n += 1;
    }
}

/// Passes on the numbers from `input` that `prime` does not divide, until either end goes away.
async fn filter(mut input: Receiver<i64>, output: Sender<i64>, prime: i64) {
    while let Some(n) = input.recv().await {
        if n % prime != 0 && output.send(n).await.is_err() {
            return;
        }
    }
}

#[tokio::main]
async fn main() {
    let n: i64 = env::args()
        .nth(1)
        .expect("usage: main <n>")
        .parse()
        .expect("n must be a non-negative integer");

    // tokio's mpsc has no capacity 0; capacity 1 is the closest (SPEC, "Bounded, blocking
    // channels"). The tasks are never awaited: returning from `main` drops the runtime, which
    // drops every task at once (SPEC, "Shut down", option 2).
    let (tx, mut numbers) = channel::<i64>(1);
    tokio::spawn(generate(tx));

    let mut last: i64 = 0;
    let mut sum: i64 = 0;
    for _ in 0..n {
        let prime = numbers.recv().await.expect("the generator never stops");
        last = prime;
        sum += prime;
        let (tx, rx) = channel::<i64>(1);
        let input = std::mem::replace(&mut numbers, rx);
        tokio::spawn(filter(input, tx, prime));
    }

    println!("primes: {n}");
    println!("last: {last}");
    println!("sum: {sum}");
}
