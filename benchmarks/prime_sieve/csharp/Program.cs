// prime_sieve: the concurrent prime sieve, one task per stage, connected by rendezvous channels (bounded, capacity 0).
using System.Globalization;
using System.Threading.Channels;

long n = long.Parse(args[0], CultureInfo.InvariantCulture);
using var cts = new CancellationTokenSource();
CancellationToken token = cts.Token;

var ch = NewChannel();
var tasks = new List<Task>();
var first = ch;
tasks.Add(Task.Run(() => Generate(first.Writer, token)));

long last = 0;
long sum = 0;
for (long k = 0; k < n; k++)
{
    long prime = await ch.Reader.ReadAsync();
    last = prime;
    sum += prime;
    var input = ch;
    var next = NewChannel();
    tasks.Add(Task.Run(() => Filter(input.Reader, next.Writer, prime, token)));
    ch = next;
}

// Shut the pipeline down by cancelling every task at once and waiting for them (SPEC "Shut
// down", option 2). Every blocked read and write fails with OperationCanceledException.
cts.Cancel();
try
{
    await Task.WhenAll(tasks);
}
catch (OperationCanceledException)
{
}

Console.WriteLine($"primes: {n}");
Console.WriteLine($"last: {last}");
Console.WriteLine($"sum: {sum}");

static Channel<long> NewChannel() =>
    Channel.CreateBounded<long>(new BoundedChannelOptions(0)
    {
        FullMode = BoundedChannelFullMode.Wait,
        SingleReader = true,
        SingleWriter = true,
    });

// Sends 2, 3, 4 and so on until cancelled.
static async Task Generate(ChannelWriter<long> output, CancellationToken token)
{
    for (long i = 2; ; i++)
    {
        await output.WriteAsync(i, token);
    }
}

// Passes on the numbers that prime does not divide, until cancelled.
static async Task Filter(ChannelReader<long> input, ChannelWriter<long> output, long prime, CancellationToken token)
{
    while (true)
    {
        long m = await input.ReadAsync(token);
        if (m % prime != 0)
        {
            await output.WriteAsync(m, token);
        }
    }
}
