// json_roundtrip: parses an array of JSON records, aggregates and transforms them, and
// serializes the kept records back to compact JSON, `reps` times.

using System.Globalization;
using System.Text.Json;

const uint FnvOffset = 2166136261;
const uint FnvPrime = 16777619;

string text = File.ReadAllText(args[0]);
int reps = int.Parse(args[1], CultureInfo.InvariantCulture);

// camelCase property names, matching the lowercase JSON keys.
var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);

long recordsN = 0, activeN = 0, scoreSum = 0, tagsN = 0, historyN = 0, amountSum = 0, outputBytes = 0;
uint h = FnvOffset;

for (int rep = 0; rep < reps; rep++)
{
    List<Record> records = JsonSerializer.Deserialize<List<Record>>(text, options)!;
    var kept = new List<Kept>();
    foreach (Record r in records)
    {
        long total = 0;
        foreach (Entry e in r.History)
        {
            total += e.Amount;
        }
        recordsN++;
        scoreSum += r.Score;
        tagsN += r.Tags.Count;
        historyN += r.History.Count;
        amountSum += total;
        if (r.Active)
        {
            activeN++;
            kept.Add(new Kept(r.Id, r.Name, r.Score + 100 * r.Tags.Count, r.Tags, r.Address, r.History, total));
        }
    }
    byte[] output = JsonSerializer.SerializeToUtf8Bytes(kept, options);
    outputBytes += output.Length;
    if (rep == reps - 1)
    {
        foreach (byte b in output)
        {
            h = (h ^ b) * FnvPrime;
        }
    }
}

Console.Write(
    $"records {recordsN}\n" +
    $"active {activeN}\n" +
    $"score_sum {scoreSum}\n" +
    $"tags {tagsN}\n" +
    $"history {historyN}\n" +
    $"amount_sum {amountSum}\n" +
    $"output_bytes {outputBytes}\n" +
    $"output_fnv1a {h}\n");

record Address(string Street, string City, int Zip);

record Entry(int Day, int Amount);

record Record(int Id, string Name, bool Active, int Score, List<string> Tags, Address Address, List<Entry> History);

// Properties are written in declaration order: the output's key order.
record Kept(int Id, string Name, int Score, List<string> Tags, Address Address, List<Entry> History, long Total);
