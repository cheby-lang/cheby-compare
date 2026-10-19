// Spectral norm: the benchmarks-game power method on the matrix
// A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.
using System.Globalization;

int n = int.Parse(args[0], CultureInfo.InvariantCulture);
double[] u = new double[n];
Array.Fill(u, 1.0);
double[] v = new double[n];
double[] tmp = new double[n];
for (int round = 0; round < 10; round++)
{
    Spectral.TimesAtA(u, tmp, v);
    Spectral.TimesAtA(v, tmp, u);
}
double vBv = 0.0, vv = 0.0;
for (int i = 0; i < n; i++)
{
    vBv += u[i] * v[i];
    vv += v[i] * v[i];
}
long result = vv == 0.0 ? 0 : (long)Math.Round(Math.Sqrt(vBv / vv) * 1e9, MidpointRounding.AwayFromZero);
Console.WriteLine(result);

static class Spectral
{
    // The entry A(i, j) of the matrix.
    static double A(int i, int j) => 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);

    // Writes A times x into output.
    static void TimesA(double[] x, double[] output)
    {
        for (int i = 0; i < output.Length; i++)
        {
            double sum = 0.0;
            for (int j = 0; j < x.Length; j++)
            {
                sum += A(i, j) * x[j];
            }
            output[i] = sum;
        }
    }

    // Writes A transposed times x into output.
    static void TimesAt(double[] x, double[] output)
    {
        for (int i = 0; i < output.Length; i++)
        {
            double sum = 0.0;
            for (int j = 0; j < x.Length; j++)
            {
                sum += A(j, i) * x[j];
            }
            output[i] = sum;
        }
    }

    // Writes A transposed times A times x into output, using tmp.
    public static void TimesAtA(double[] x, double[] tmp, double[] output)
    {
        TimesA(x, tmp);
        TimesAt(tmp, output);
    }
}
