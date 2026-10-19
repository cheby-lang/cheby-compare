//! prime_sieve: the concurrent prime sieve, one OS thread per stage, connected by rendezvous
//! channels.

use std::env;
use std::sync::mpsc::{Receiver, SyncSender, sync_channel};
use std::thread;

/// Sends 2, 3, 4 and so on until the receiving end goes away.
fn generate(output: SyncSender<i64>) {
    let mut n = 2;
    while output.send(n).is_ok() {
        n += 1;
    }
}

/// Passes on the numbers from `input` that `prime` does not divide, until either end goes away.
fn filter(input: Receiver<i64>, output: SyncSender<i64>, prime: i64) {
    for n in input {
        if n % prime != 0 && output.send(n).is_err() {
            return;
        }
    }
}

fn main() {
    let n: i64 = env::args()
        .nth(1)
        .expect("usage: main <n>")
        .parse()
        .expect("n must be a non-negative integer");

    // The threads are never joined: returning from `main` ends the process with them still
    // blocked (SPEC, "Shut down"), so nothing waits for them to sieve past the n-th prime.
    let (tx, mut numbers) = sync_channel::<i64>(0);
    thread::spawn(move || generate(tx));

    let mut last: i64 = 0;
    let mut sum: i64 = 0;
    for _ in 0..n {
        let prime = numbers.recv().expect("the generator never stops");
        last = prime;
        sum += prime;
        let (tx, rx) = sync_channel::<i64>(0);
        let input = std::mem::replace(&mut numbers, rx);
        thread::spawn(move || filter(input, tx, prime));
    }

    println!("primes: {n}");
    println!("last: {last}");
    println!("sum: {sum}");
}
