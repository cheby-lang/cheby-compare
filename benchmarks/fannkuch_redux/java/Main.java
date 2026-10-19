// Fannkuch-redux: flips over every permutation of 0..n, in the order the counting algorithm
// generates them. Prints the alternating checksum and the maximum flip count.
public class Main {
    /** Returns {checksum, maxFlips} over all permutations of 0..n, n >= 1. */
    static int[] fannkuch(int n) {
        int[] perm1 = new int[n];
        for (int i = 0; i < n; i++) {
            perm1[i] = i;
        }
        int[] perm = new int[n];
        int[] count = new int[n];
        int maxFlips = 0;
        int checksum = 0;
        long permIndex = 0;
        int r = n;
        while (true) {
            while (r != 1) {
                count[r - 1] = r;
                r--;
            }

            System.arraycopy(perm1, 0, perm, 0, n);
            int flips = 0;
            int k = perm[0];
            while (k != 0) {
                for (int i = 0, j = k; i < j; i++, j--) {
                    int t = perm[i];
                    perm[i] = perm[j];
                    perm[j] = t;
                }
                flips++;
                k = perm[0];
            }
            maxFlips = Math.max(maxFlips, flips);
            checksum += (permIndex % 2 == 0) ? flips : -flips;

            while (true) {
                if (r == n) {
                    return new int[] {checksum, maxFlips};
                }
                int first = perm1[0];
                for (int i = 0; i < r; i++) {
                    perm1[i] = perm1[i + 1];
                }
                perm1[r] = first;
                count[r]--;
                if (count[r] > 0) {
                    break;
                }
                r++;
            }
            permIndex++;
        }
    }

    public static void main(String[] args) {
        int n = Integer.parseInt(args[0]);
        int[] result = fannkuch(Math.max(n, 1));
        System.out.println(result[0]);
        System.out.println("Pfannkuchen(" + n + ") = " + result[1]);
    }
}
