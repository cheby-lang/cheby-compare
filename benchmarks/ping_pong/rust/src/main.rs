//! ping_pong: two OS threads exchange `n` messages over two rendezvous channels.

use std::env;
use std::sync::mpsc::{Receiver, SyncSender, sync_channel};
use std::thread;

/// Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
fn echo(n: i64, ping: Receiver<i64>, pong: SyncSender<i64>) {
    for _ in 0..n {
        let x = ping.recv().expect("ping closed");
        pong.send(x + 1).expect("pong closed");
    }
}

fn main() {
    let n: i64 = env::args()
        .nth(1)
        .expect("usage: main <n>")
        .parse()
        .expect("n must be a non-negative integer");

    let (ping_tx, ping_rx) = sync_channel::<i64>(0);
    let (pong_tx, pong_rx) = sync_channel::<i64>(0);
    let b = thread::spawn(move || echo(n, ping_rx, pong_tx));

    let mut sum: i64 = 0;
    for i in 1..=n {
        ping_tx.send(i).expect("ping closed");
        sum += pong_rx.recv().expect("pong closed");
    }
    b.join().expect("task B panicked");

    println!("{n}");
    println!("{sum}");
}
