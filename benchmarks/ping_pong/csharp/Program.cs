// ping_pong: two tasks pass a number back and forth n times over two rendezvous channels (bounded, capacity 0).
using System.Globalization;
using System.Threading.Channels;

static Channel<long> NewChannel() =>
    Channel.CreateBounded<long>(new BoundedChannelOptions(0)
    {
        FullMode = BoundedChannelFullMode.Wait,
        SingleReader = true,
        SingleWriter = true,
    });

// Task B: answers each of the n values from ping with the value plus one on pong.
static async Task Echo(long n, ChannelReader<long> ping, ChannelWriter<long> pong)
{
    for (long i = 0; i < n; i++)
    {
        long x = await ping.ReadAsync();
        await pong.WriteAsync(x + 1);
    }
}

long n = long.Parse(args[0], CultureInfo.InvariantCulture);
var ping = NewChannel();
var pong = NewChannel();
Task b = Task.Run(() => Echo(n, ping.Reader, pong.Writer));

// Task A is the async main itself.
long sum = 0;
for (long i = 1; i <= n; i++)
{
    await ping.Writer.WriteAsync(i);
    sum += await pong.Reader.ReadAsync();
}
await b;

Console.WriteLine(n);
Console.WriteLine(sum);
