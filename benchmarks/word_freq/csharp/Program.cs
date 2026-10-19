// word_freq: counts the words of a file and prints the 20 most frequent.

using System.Text;

const int Top = 20;

string text = File.ReadAllText(args[0], Encoding.ASCII);

var counts = new Dictionary<string, int>();
long total = 0;
foreach (string word in text.Split([' ', '\n'], StringSplitOptions.RemoveEmptyEntries))
{
    counts.TryGetValue(word, out int c);
    counts[word] = c + 1;
    total++;
}

var ranked = counts.ToList();
ranked.Sort((a, b) =>
{
    int byCount = b.Value.CompareTo(a.Value);
    return byCount != 0 ? byCount : string.CompareOrdinal(a.Key, b.Key);
});

var sb = new StringBuilder();
sb.Append("total ").Append(total).Append('\n');
sb.Append("distinct ").Append(counts.Count).Append('\n');
foreach (var (word, count) in ranked.Take(Top))
{
    sb.Append(count).Append(' ').Append(word).Append('\n');
}
Console.Out.Write(sb.ToString());
