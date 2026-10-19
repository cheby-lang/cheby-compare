//! Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.

const MAX_ITER: u32 = 50;

/// The number of iterations before the point (cr, ci) escapes, or `MAX_ITER`.
fn escape_time(cr: f64, ci: f64) -> u32 {
    let (mut zr, mut zi) = (0.0f64, 0.0f64);
    let mut i = 0;
    while i < MAX_ITER {
        let zr2 = zr * zr;
        let zi2 = zi * zi;
        if zr2 + zi2 > 4.0 {
            break;
        }
        zi = 2.0 * zr * zi + ci;
        zr = zr2 - zi2 + cr;
        i += 1;
    }
    i
}

fn main() {
    let n: u64 = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .expect("usage: main N");
    let nf = n as f64;
    let mut inside: u64 = 0;
    let mut iterations: u64 = 0;
    let mut checksum: u64 = 0;
    for y in 0..n {
        let ci = 2.0 * y as f64 / nf - 1.0;
        for x in 0..n {
            let cr = 2.0 * x as f64 / nf - 1.5;
            let i = escape_time(cr, ci);
            iterations += u64::from(i);
            if i == MAX_ITER {
                inside += 1;
                checksum += y * n + x;
            }
        }
    }
    println!("inside {inside}");
    println!("iterations {iterations}");
    println!("checksum {}", checksum % (1 << 32));
}
