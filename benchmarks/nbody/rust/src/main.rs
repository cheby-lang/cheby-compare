//! n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
//! Prints the total energy before and after, as round(e * 10^9).

// The initial conditions keep the canonical 18-digit constants of the benchmark.
#![allow(clippy::excessive_precision)]

use std::env;
use std::f64::consts::PI;

const SOLAR_MASS: f64 = 4.0 * PI * PI;
const DAYS_PER_YEAR: f64 = 365.24;
const DT: f64 = 0.01;

#[derive(Clone, Copy)]
struct Body {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
}

fn planet(pos: [f64; 3], vel: [f64; 3], mass: f64) -> Body {
    Body {
        x: pos[0],
        y: pos[1],
        z: pos[2],
        vx: vel[0] * DAYS_PER_YEAR,
        vy: vel[1] * DAYS_PER_YEAR,
        vz: vel[2] * DAYS_PER_YEAR,
        mass: mass * SOLAR_MASS,
    }
}

fn initial_bodies() -> [Body; 5] {
    let sun = Body {
        x: 0.0,
        y: 0.0,
        z: 0.0,
        vx: 0.0,
        vy: 0.0,
        vz: 0.0,
        mass: SOLAR_MASS,
    };
    let jupiter = planet(
        [
            4.84143144246472090e+00,
            -1.16032004402742839e+00,
            -1.03622044471123109e-01,
        ],
        [
            1.66007664274403694e-03,
            7.69901118419740425e-03,
            -6.90460016972063023e-05,
        ],
        9.54791938424326609e-04,
    );
    let saturn = planet(
        [
            8.34336671824457987e+00,
            4.12479856412430479e+00,
            -4.03523417114321381e-01,
        ],
        [
            -2.76742510726862411e-03,
            4.99852801234917238e-03,
            2.30417297573763929e-05,
        ],
        2.85885980666130812e-04,
    );
    let uranus = planet(
        [
            1.28943695621391310e+01,
            -1.51111514016986312e+01,
            -2.23307578892655734e-01,
        ],
        [
            2.96460137564761618e-03,
            2.37847173959480950e-03,
            -2.96589568540237556e-05,
        ],
        4.36624404335156298e-05,
    );
    let neptune = planet(
        [
            1.53796971148509165e+01,
            -2.59193146099879641e+01,
            1.79258772950371181e-01,
        ],
        [
            2.68067772490389322e-03,
            1.62824170038242295e-03,
            -9.51592254519715870e-05,
        ],
        5.15138902046611451e-05,
    );
    [sun, jupiter, saturn, uranus, neptune]
}

fn offset_momentum(bodies: &mut [Body]) {
    let (mut px, mut py, mut pz) = (0.0, 0.0, 0.0);
    for b in bodies.iter() {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    let sun = &mut bodies[0];
    sun.vx = -px / SOLAR_MASS;
    sun.vy = -py / SOLAR_MASS;
    sun.vz = -pz / SOLAR_MASS;
}

fn energy(bodies: &[Body]) -> f64 {
    let mut e = 0.0;
    for (i, bi) in bodies.iter().enumerate() {
        e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz);
        for bj in &bodies[i + 1..] {
            let dx = bi.x - bj.x;
            let dy = bi.y - bj.y;
            let dz = bi.z - bj.z;
            e -= bi.mass * bj.mass / (dx * dx + dy * dy + dz * dz).sqrt();
        }
    }
    e
}

fn advance(bodies: &mut [Body]) {
    for i in 0..bodies.len() {
        let (head, tail) = bodies.split_at_mut(i + 1);
        let bi = &mut head[i];
        for bj in tail.iter_mut() {
            let dx = bi.x - bj.x;
            let dy = bi.y - bj.y;
            let dz = bi.z - bj.z;
            let d2 = dx * dx + dy * dy + dz * dz;
            let mag = DT / (d2 * d2.sqrt());
            let mi_mag = bi.mass * mag;
            let mj_mag = bj.mass * mag;
            bi.vx -= dx * mj_mag;
            bi.vy -= dy * mj_mag;
            bi.vz -= dz * mj_mag;
            bj.vx += dx * mi_mag;
            bj.vy += dy * mi_mag;
            bj.vz += dz * mi_mag;
        }
    }
    for b in bodies.iter_mut() {
        b.x += DT * b.vx;
        b.y += DT * b.vy;
        b.z += DT * b.vz;
    }
}

fn scaled(e: f64) -> i64 {
    (e * 1e9).round() as i64
}

fn main() {
    let steps: u64 = env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .expect("usage: main <steps>");
    let mut bodies = initial_bodies();
    offset_momentum(&mut bodies);
    println!("{}", scaled(energy(&bodies)));
    for _ in 0..steps {
        advance(&mut bodies);
    }
    println!("{}", scaled(energy(&bodies)));
}
