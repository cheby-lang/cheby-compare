//! ping_pong: two tokio tasks exchange `n` messages over two one-slot channels.

use std::env;
use tokio::sync::mpsc::{Receiver, Sender, channel};

/// Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
async fn echo(n: i64, mut ping: Receiver<i64>, pong: Sender<i64>) {
    for _ in 0..n {
        let x = ping.recv().await.expect("ping closed");
        pong.send(x + 1).await.expect("pong closed");
    }
}

/// Task A: sends 1..=n on `ping` and returns the sum of the answers from `pong`.
async fn play(n: i64, ping: Sender<i64>, mut pong: Receiver<i64>) -> i64 {
    let mut sum = 0;
    for i in 1..=n {
        ping.send(i).await.expect("ping closed");
        sum += pong.recv().await.expect("pong closed");
    }
    sum
}

#[tokio::main]
async fn main() {
    let n: i64 = env::args()
        .nth(1)
        .expect("usage: main <n>")
        .parse()
        .expect("n must be a non-negative integer");

    // tokio's mpsc has no capacity 0; capacity 1 is the closest (SPEC, "Rendezvous where
    // possible"). The main future runs through `block_on` on the main thread, not on a worker,
    // so A is spawned as a task like B and main only awaits them.
    let (ping_tx, ping_rx) = channel::<i64>(1);
    let (pong_tx, pong_rx) = channel::<i64>(1);
    let b = tokio::spawn(echo(n, ping_rx, pong_tx));
    let a = tokio::spawn(play(n, ping_tx, pong_rx));
    let sum = a.await.expect("task A panicked");
    b.await.expect("task B panicked");

    println!("{n}");
    println!("{sum}");
}
