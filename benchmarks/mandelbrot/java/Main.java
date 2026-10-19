// Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.
public class Main {
    private static final int MAX_ITER = 50;

    /** The number of iterations before the point (cr, ci) escapes, or MAX_ITER. */
    static int escapeTime(double cr, double ci) {
        double zr = 0.0, zi = 0.0;
        int i = 0;
        while (i < MAX_ITER) {
            double zr2 = zr * zr;
            double zi2 = zi * zi;
            if (zr2 + zi2 > 4.0) {
                break;
            }
            zi = 2.0 * zr * zi + ci;
            zr = zr2 - zi2 + cr;
            i++;
        }
        return i;
    }

    public static void main(String[] args) {
        long n = Long.parseLong(args[0]);
        double nf = (double) n;
        long inside = 0;
        long iterations = 0;
        long checksum = 0;
        for (long y = 0; y < n; y++) {
            double ci = 2.0 * y / nf - 1.0;
            for (long x = 0; x < n; x++) {
                double cr = 2.0 * x / nf - 1.5;
                int i = escapeTime(cr, ci);
                iterations += i;
                if (i == MAX_ITER) {
                    inside++;
                    checksum += y * n + x;
                }
            }
        }
        System.out.println("inside " + inside);
        System.out.println("iterations " + iterations);
        System.out.println("checksum " + (checksum & 0xFFFFFFFFL));
    }
}
