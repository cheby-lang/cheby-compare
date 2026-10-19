// Mandelbrot set on an N x N grid: counts the points inside, sums the iterations, and prints a
// checksum of the inside points' positions.
using System.Globalization;

const int MaxIter = 50;

long n = long.Parse(args[0], CultureInfo.InvariantCulture);
double nf = n;
long inside = 0, iterations = 0, checksum = 0;
for (long y = 0; y < n; y++)
{
    double ci = 2.0 * y / nf - 1.0;
    for (long x = 0; x < n; x++)
    {
        double cr = 2.0 * x / nf - 1.5;
        int i = EscapeTime(cr, ci);
        iterations += i;
        if (i == MaxIter)
        {
            inside++;
            checksum += y * n + x;
        }
    }
}
Console.WriteLine($"inside {inside}");
Console.WriteLine($"iterations {iterations}");
Console.WriteLine($"checksum {checksum % (1L << 32)}");

// The number of iterations before the point (cr, ci) escapes, or MaxIter.
static int EscapeTime(double cr, double ci)
{
    double zr = 0.0, zi = 0.0;
    int i = 0;
    while (i < MaxIter)
    {
        double zr2 = zr * zr;
        double zi2 = zi * zi;
        if (zr2 + zi2 > 4.0)
        {
            break;
        }
        zi = 2.0 * zr * zi + ci;
        zr = zr2 - zi2 + cr;
        i++;
    }
    return i;
}
