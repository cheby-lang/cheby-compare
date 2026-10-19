// n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).
using System.Globalization;

long steps = long.Parse(args[0], CultureInfo.InvariantCulture);
Body[] bodies = NBody.InitialBodies();
NBody.OffsetMomentum(bodies);
Console.WriteLine(NBody.Scaled(NBody.Energy(bodies)));
for (long s = 0; s < steps; s++)
{
    NBody.Advance(bodies);
}
Console.WriteLine(NBody.Scaled(NBody.Energy(bodies)));

struct Body
{
    public double X, Y, Z, Vx, Vy, Vz, Mass;
}

static class NBody
{
    const double SolarMass = 4.0 * Math.PI * Math.PI;
    const double DaysPerYear = 365.24;
    const double Dt = 0.01;

    static Body Planet(double x, double y, double z, double vx, double vy, double vz, double mass) =>
        new()
        {
            X = x,
            Y = y,
            Z = z,
            Vx = vx * DaysPerYear,
            Vy = vy * DaysPerYear,
            Vz = vz * DaysPerYear,
            Mass = mass * SolarMass,
        };

    public static Body[] InitialBodies() =>
    [
        new Body { Mass = SolarMass },
        Planet(
            4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
            1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
            9.54791938424326609e-04),
        Planet(
            8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
            -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
            2.85885980666130812e-04),
        Planet(
            1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
            2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
            4.36624404335156298e-05),
        Planet(
            1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
            2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
            5.15138902046611451e-05),
    ];

    public static void OffsetMomentum(Body[] bodies)
    {
        double px = 0.0, py = 0.0, pz = 0.0;
        foreach (Body b in bodies)
        {
            px += b.Vx * b.Mass;
            py += b.Vy * b.Mass;
            pz += b.Vz * b.Mass;
        }
        bodies[0].Vx = -px / SolarMass;
        bodies[0].Vy = -py / SolarMass;
        bodies[0].Vz = -pz / SolarMass;
    }

    public static double Energy(Body[] bodies)
    {
        double e = 0.0;
        for (int i = 0; i < bodies.Length; i++)
        {
            ref readonly Body b = ref bodies[i];
            e += 0.5 * b.Mass * (b.Vx * b.Vx + b.Vy * b.Vy + b.Vz * b.Vz);
            for (int j = i + 1; j < bodies.Length; j++)
            {
                ref readonly Body o = ref bodies[j];
                double dx = b.X - o.X;
                double dy = b.Y - o.Y;
                double dz = b.Z - o.Z;
                e -= b.Mass * o.Mass / Math.Sqrt(dx * dx + dy * dy + dz * dz);
            }
        }
        return e;
    }

    public static void Advance(Body[] bodies)
    {
        for (int i = 0; i < bodies.Length; i++)
        {
            ref Body a = ref bodies[i];
            for (int j = i + 1; j < bodies.Length; j++)
            {
                ref Body b = ref bodies[j];
                double dx = a.X - b.X;
                double dy = a.Y - b.Y;
                double dz = a.Z - b.Z;
                double d2 = dx * dx + dy * dy + dz * dz;
                double mag = Dt / (d2 * Math.Sqrt(d2));
                double aMag = a.Mass * mag;
                double bMag = b.Mass * mag;
                a.Vx -= dx * bMag;
                a.Vy -= dy * bMag;
                a.Vz -= dz * bMag;
                b.Vx += dx * aMag;
                b.Vy += dy * aMag;
                b.Vz += dz * aMag;
            }
        }
        foreach (ref Body b in bodies.AsSpan())
        {
            b.X += Dt * b.Vx;
            b.Y += Dt * b.Vy;
            b.Z += Dt * b.Vz;
        }
    }

    public static long Scaled(double e) => (long)Math.Round(e * 1e9, MidpointRounding.AwayFromZero);
}
