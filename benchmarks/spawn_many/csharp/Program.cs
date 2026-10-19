// spawn_many: spawns n short tasks in batches of 1000, joins each batch, and prints the sum.
using System.Globalization;

const long B = 1000;

long n = long.Parse(args[0], CultureInfo.InvariantCulture);
long sum = 0;
for (long start = 0; start < n; start += B)
{
    sum += await SpawnAndJoin(start, Math.Min(B, n - start));
}
Console.WriteLine($"tasks: {n}");
Console.WriteLine($"sum: {sum}");

// One batch: one task per index, all spawned before any join.
static async Task<long> SpawnAndJoin(long start, long count)
{
    var batch = new Task<long>[count];
    for (long j = 0; j < count; j++)
    {
        long index = start + j;
        batch[j] = Task.Run(() => Work(index));
    }
    long[] results = await Task.WhenAll(batch);
    long total = 0;
    foreach (long r in results)
    {
        total += r;
    }
    return total;
}

// Ten steps of the MINSTD generator, starting from index + 1.
static long Work(long index)
{
    const long Modulus = 2147483647;
    const long Multiplier = 48271;
    long x = index + 1;
    for (int r = 0; r < 10; r++)
    {
        x = x * Multiplier % Modulus;
    }
    return x;
}
