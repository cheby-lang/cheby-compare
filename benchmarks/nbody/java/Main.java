// n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).
public class Main {
    private static final double PI = Math.PI;
    private static final double SOLAR_MASS = 4.0 * PI * PI;
    private static final double DAYS_PER_YEAR = 365.24;
    private static final double DT = 0.01;

    /** One body: position, velocity and mass, updated in place. */
    static final class Body {
        double x, y, z, vx, vy, vz, mass;

        Body(double x, double y, double z, double vx, double vy, double vz, double mass) {
            this.x = x;
            this.y = y;
            this.z = z;
            this.vx = vx;
            this.vy = vy;
            this.vz = vz;
            this.mass = mass;
        }

        static Body planet(double x, double y, double z,
                           double vx, double vy, double vz, double mass) {
            return new Body(x, y, z,
                    vx * DAYS_PER_YEAR, vy * DAYS_PER_YEAR, vz * DAYS_PER_YEAR,
                    mass * SOLAR_MASS);
        }
    }

    static Body[] initialBodies() {
        return new Body[] {
            new Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS),
            Body.planet( // Jupiter
                    4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
                    1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
                    9.54791938424326609e-04),
            Body.planet( // Saturn
                    8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
                    -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
                    2.85885980666130812e-04),
            Body.planet( // Uranus
                    1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
                    2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
                    4.36624404335156298e-05),
            Body.planet( // Neptune
                    1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
                    2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
                    5.15138902046611451e-05),
        };
    }

    static void offsetMomentum(Body[] bodies) {
        double px = 0.0, py = 0.0, pz = 0.0;
        for (Body b : bodies) {
            px += b.vx * b.mass;
            py += b.vy * b.mass;
            pz += b.vz * b.mass;
        }
        Body sun = bodies[0];
        sun.vx = -px / SOLAR_MASS;
        sun.vy = -py / SOLAR_MASS;
        sun.vz = -pz / SOLAR_MASS;
    }

    static double energy(Body[] bodies) {
        double e = 0.0;
        for (int i = 0; i < bodies.length; i++) {
            Body bi = bodies[i];
            e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz);
            for (int j = i + 1; j < bodies.length; j++) {
                Body bj = bodies[j];
                double dx = bi.x - bj.x;
                double dy = bi.y - bj.y;
                double dz = bi.z - bj.z;
                e -= bi.mass * bj.mass / Math.sqrt(dx * dx + dy * dy + dz * dz);
            }
        }
        return e;
    }

    static void advance(Body[] bodies) {
        for (int i = 0; i < bodies.length; i++) {
            Body a = bodies[i];
            for (int j = i + 1; j < bodies.length; j++) {
                Body b = bodies[j];
                double dx = a.x - b.x;
                double dy = a.y - b.y;
                double dz = a.z - b.z;
                double d2 = dx * dx + dy * dy + dz * dz;
                double mag = DT / (d2 * Math.sqrt(d2));
                double aMag = a.mass * mag;
                double bMag = b.mass * mag;
                a.vx -= dx * bMag;
                a.vy -= dy * bMag;
                a.vz -= dz * bMag;
                b.vx += dx * aMag;
                b.vy += dy * aMag;
                b.vz += dz * aMag;
            }
        }
        for (Body b : bodies) {
            b.x += DT * b.vx;
            b.y += DT * b.vy;
            b.z += DT * b.vz;
        }
    }

    /** round(e * 10^9), halves away from zero. */
    static long scaled(double e) {
        double x = e * 1.0e9;
        return x < 0 ? -Math.round(-x) : Math.round(x);
    }

    public static void main(String[] args) {
        long steps = Long.parseLong(args[0]);
        Body[] bodies = initialBodies();
        offsetMomentum(bodies);
        System.out.println(scaled(energy(bodies)));
        for (long s = 0; s < steps; s++) {
            advance(bodies);
        }
        System.out.println(scaled(energy(bodies)));
    }
}
