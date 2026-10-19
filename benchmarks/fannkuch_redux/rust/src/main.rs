//! Fannkuch-redux: flips over every permutation of 0..n, in the order the
//! counting algorithm generates them. Prints the alternating checksum and the
//! maximum flip count.

use std::env;

/// Returns (checksum, max_flips) over all permutations of 0..n, n >= 1.
fn fannkuch(n: usize) -> (i64, i64) {
    let mut perm1: Vec<usize> = (0..n).collect();
    let mut perm = vec![0usize; n];
    let mut count = vec![0usize; n];
    let mut max_flips = 0i64;
    let mut checksum = 0i64;
    let mut perm_index = 0u64;
    let mut r = n;
    loop {
        while r != 1 {
            count[r - 1] = r;
            r -= 1;
        }

        perm.copy_from_slice(&perm1);
        let mut flips = 0i64;
        let mut k = perm[0];
        while k != 0 {
            perm[..=k].reverse();
            flips += 1;
            k = perm[0];
        }
        max_flips = max_flips.max(flips);
        checksum += if perm_index.is_multiple_of(2) { flips } else { -flips };

        loop {
            if r == n {
                return (checksum, max_flips);
            }
            perm1[..=r].rotate_left(1);
            count[r] -= 1;
            if count[r] > 0 {
                break;
            }
            r += 1;
        }
        perm_index += 1;
    }
}

fn main() {
    let n: usize = env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .expect("usage: main N");
    let (checksum, max_flips) = fannkuch(n.max(1));
    println!("{checksum}");
    println!("Pfannkuchen({n}) = {max_flips}");
}
