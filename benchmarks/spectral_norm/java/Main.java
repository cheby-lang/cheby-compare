// Spectral norm: the benchmarks-game power method on the matrix
// A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.
public class Main {
    /** The entry A(i, j) of the matrix. */
    static double entry(int i, int j) {
        return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);
    }

    /** Writes A times x into out. */
    static void timesA(double[] x, double[] out) {
        for (int i = 0; i < out.length; i++) {
            double sum = 0.0;
            for (int j = 0; j < x.length; j++) {
                sum += entry(i, j) * x[j];
            }
            out[i] = sum;
        }
    }

    /** Writes A transposed times x into out. */
    static void timesAt(double[] x, double[] out) {
        for (int i = 0; i < out.length; i++) {
            double sum = 0.0;
            for (int j = 0; j < x.length; j++) {
                sum += entry(j, i) * x[j];
            }
            out[i] = sum;
        }
    }

    /** Writes A transposed times A times x into out, using tmp. */
    static void timesAtA(double[] x, double[] tmp, double[] out) {
        timesA(x, tmp);
        timesAt(tmp, out);
    }

    static double dot(double[] x, double[] y) {
        double sum = 0.0;
        for (int i = 0; i < x.length; i++) {
            sum += x[i] * y[i];
        }
        return sum;
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        double[] u = new double[n];
        java.util.Arrays.fill(u, 1.0);
        double[] v = new double[n];
        double[] tmp = new double[n];
        for (int round = 0; round < 10; round++) {
            timesAtA(u, tmp, v);
            timesAtA(v, tmp, u);
        }
        double vv = dot(v, v);
        long result = 0;
        if (vv != 0.0) {
            double x = Math.sqrt(dot(u, v) / vv) * 1e9;
            result = x < 0 ? -Math.round(-x) : Math.round(x);
        }
        System.out.println(result);
    }
}
