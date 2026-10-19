// lru_cache: an LRU cache of fixed capacity under a skewed pseudo-random key stream; prints the
// hits, misses, a sum of the hit values and a checksum of the final contents in recency order.

using System.Globalization;

const long LehmerM = 2147483647;
const long LehmerA = 48271;
const long Seed = 42;
const long HotPercent = 80;
const long Modulus = 1000000007;

long capacity = long.Parse(args[0], CultureInfo.InvariantCulture);
long ops = long.Parse(args[1], CultureInfo.InvariantCulture);
long hot = capacity;
long cold = capacity * 15;

// Key -> list node; the list runs from least recently used (first) to most recently used (last).
var index = new Dictionary<long, LinkedListNode<(long Key, long Value)>>((int)capacity);
var order = new LinkedList<(long Key, long Value)>();

long hits = 0, misses = 0, values = 0;
long state = Seed;

for (long i = 0; i < ops; i++)
{
    state = state * LehmerA % LehmerM;
    long draw = state / 100;
    long key = state % 100 < HotPercent ? draw % hot : hot + draw % cold;

    if (index.TryGetValue(key, out var node))
    {
        order.Remove(node);
        order.AddLast(node);
        hits++;
        values = (values + node.Value.Value) % Modulus;
    }
    else
    {
        if (index.Count == capacity)
        {
            var oldest = order.First!;
            order.RemoveFirst();
            index.Remove(oldest.Value.Key);
            oldest.Value = (key, key * 2 + 1);
            order.AddLast(oldest);
            index.Add(key, oldest);
        }
        else
        {
            index.Add(key, order.AddLast((key, key * 2 + 1)));
        }
        misses++;
    }
}

long checksum = 0;
long position = 1;
foreach (var (key, _) in order)
{
    checksum = (checksum + position * key) % Modulus;
    position++;
}

Console.Write($"hits {hits}\nmisses {misses}\nvalues {values}\nchecksum {checksum}\n");
