//! Spectral norm: the benchmarks-game power method on the matrix
//! A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.

use std::env;

/// The entry A(i, j) of the matrix.
fn entry(i: usize, j: usize) -> f64 {
    1.0 / ((i + j) * (i + j + 1) / 2 + i + 1) as f64
}

/// Writes A times `x` into `out`.
fn times_a(x: &[f64], out: &mut [f64]) {
    for (i, o) in out.iter_mut().enumerate() {
        let mut sum = 0.0;
        for (j, xj) in x.iter().enumerate() {
            sum += entry(i, j) * xj;
        }
        *o = sum;
    }
}

/// Writes A transposed times `x` into `out`.
fn times_at(x: &[f64], out: &mut [f64]) {
    for (i, o) in out.iter_mut().enumerate() {
        let mut sum = 0.0;
        for (j, xj) in x.iter().enumerate() {
            sum += entry(j, i) * xj;
        }
        *o = sum;
    }
}

/// Writes A transposed times A times `x` into `out`, using `tmp`.
fn times_ata(x: &[f64], tmp: &mut [f64], out: &mut [f64]) {
    times_a(x, tmp);
    times_at(tmp, out);
}

fn dot(x: &[f64], y: &[f64]) -> f64 {
    let mut sum = 0.0;
    for (a, b) in x.iter().zip(y) {
        sum += a * b;
    }
    sum
}

fn main() {
    let n: usize = env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .expect("usage: main N");
    let mut u = vec![1.0; n];
    let mut v = vec![0.0; n];
    let mut tmp = vec![0.0; n];
    for _ in 0..10 {
        times_ata(&u, &mut tmp, &mut v);
        times_ata(&v, &mut tmp, &mut u);
    }
    let vv = dot(&v, &v);
    let result = if vv == 0.0 {
        0
    } else {
        ((dot(&u, &v) / vv).sqrt() * 1e9).round() as i64
    };
    println!("{result}");
}
