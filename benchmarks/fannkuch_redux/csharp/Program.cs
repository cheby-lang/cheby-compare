// Fannkuch-redux: counts the prefix flips of every permutation of 0..n, in the order the
// counting algorithm generates them. Prints the alternating checksum and the maximum flip count.
using System.Globalization;

int bigN = int.Parse(args[0], CultureInfo.InvariantCulture);
var (checksum, maxFlips) = Fannkuch(Math.Max(bigN, 1));
Console.WriteLine(checksum);
Console.WriteLine($"Pfannkuchen({bigN}) = {maxFlips}");

// Returns (checksum, max flips) over all permutations of 0..n, n >= 1.
static (int Checksum, int MaxFlips) Fannkuch(int n)
{
    int[] perm1 = new int[n];
    for (int i = 0; i < n; i++)
    {
        perm1[i] = i;
    }
    int[] perm = new int[n];
    int[] count = new int[n];
    int maxFlips = 0;
    int checksum = 0;
    long permIndex = 0;
    int r = n;
    while (true)
    {
        while (r != 1)
        {
            count[r - 1] = r;
            r--;
        }

        Array.Copy(perm1, perm, n);
        int flips = 0;
        int k = perm[0];
        while (k != 0)
        {
            Array.Reverse(perm, 0, k + 1);
            flips++;
            k = perm[0];
        }
        maxFlips = Math.Max(maxFlips, flips);
        checksum += permIndex % 2 == 0 ? flips : -flips;

        while (true)
        {
            if (r == n)
            {
                return (checksum, maxFlips);
            }
            int first = perm1[0];
            Array.Copy(perm1, 1, perm1, 0, r);
            perm1[r] = first;
            count[r]--;
            if (count[r] > 0)
            {
                break;
            }
            r++;
        }
        permIndex++;
    }
}
