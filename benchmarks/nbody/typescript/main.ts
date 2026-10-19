// n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).

const SOLAR_MASS = 4.0 * Math.PI * Math.PI;
const DAYS_PER_YEAR = 365.24;
const DT = 0.01;

// A plain object typed by an interface. A class with constructor parameter properties would
// emit ES2022 class fields, which V8 first initializes to undefined; the later float stores then
// box every value (about 6x slower here).
interface Body {
  x: number;
  y: number;
  z: number;
  vx: number;
  vy: number;
  vz: number;
  mass: number;
}

function planet(pos: [number, number, number], vel: [number, number, number], mass: number): Body {
  return {
    x: pos[0],
    y: pos[1],
    z: pos[2],
    vx: vel[0] * DAYS_PER_YEAR,
    vy: vel[1] * DAYS_PER_YEAR,
    vz: vel[2] * DAYS_PER_YEAR,
    mass: mass * SOLAR_MASS,
  };
}

function initialBodies(): Body[] {
  return [
    { x: 0.0, y: 0.0, z: 0.0, vx: 0.0, vy: 0.0, vz: 0.0, mass: SOLAR_MASS },
    planet(
      [4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01],
      [1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05],
      9.54791938424326609e-04,
    ),
    planet(
      [8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01],
      [-2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05],
      2.85885980666130812e-04,
    ),
    planet(
      [1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01],
      [2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05],
      4.36624404335156298e-05,
    ),
    planet(
      [1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01],
      [2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05],
      5.15138902046611451e-05,
    ),
  ];
}

function offsetMomentum(bodies: Body[]): void {
  let px = 0.0;
  let py = 0.0;
  let pz = 0.0;
  for (const b of bodies) {
    px += b.vx * b.mass;
    py += b.vy * b.mass;
    pz += b.vz * b.mass;
  }
  const sun = bodies[0];
  sun.vx = -px / SOLAR_MASS;
  sun.vy = -py / SOLAR_MASS;
  sun.vz = -pz / SOLAR_MASS;
}

function energy(bodies: Body[]): number {
  let e = 0.0;
  for (let i = 0; i < bodies.length; i++) {
    const b = bodies[i];
    e += 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz);
    for (let j = i + 1; j < bodies.length; j++) {
      const o = bodies[j];
      const dx = b.x - o.x;
      const dy = b.y - o.y;
      const dz = b.z - o.z;
      e -= (b.mass * o.mass) / Math.sqrt(dx * dx + dy * dy + dz * dz);
    }
  }
  return e;
}

function advance(bodies: Body[]): void {
  const n = bodies.length;
  for (let i = 0; i < n; i++) {
    const a = bodies[i];
    for (let j = i + 1; j < n; j++) {
      const b = bodies[j];
      const dx = a.x - b.x;
      const dy = a.y - b.y;
      const dz = a.z - b.z;
      const d2 = dx * dx + dy * dy + dz * dz;
      const mag = DT / (d2 * Math.sqrt(d2));
      const aMag = a.mass * mag;
      const bMag = b.mass * mag;
      a.vx -= dx * bMag;
      a.vy -= dy * bMag;
      a.vz -= dz * bMag;
      b.vx += dx * aMag;
      b.vy += dy * aMag;
      b.vz += dz * aMag;
    }
  }
  for (const b of bodies) {
    b.x += DT * b.vx;
    b.y += DT * b.vy;
    b.z += DT * b.vz;
  }
}

// Half away from zero (Math.round alone takes halves toward +infinity).
function scaled(e: number): number {
  const x = e * 1.0e9;
  return Math.sign(x) * Math.round(Math.abs(x));
}

function main(steps: number): void {
  const bodies = initialBodies();
  offsetMomentum(bodies);
  console.log(String(scaled(energy(bodies))));
  for (let s = 0; s < steps; s++) {
    advance(bodies);
  }
  console.log(String(scaled(energy(bodies))));
}

main(Number.parseInt(process.argv[2] ?? "0", 10));
