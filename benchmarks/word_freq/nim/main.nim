# word_freq: counts the words of a file and prints the 20 most frequent.

import std/[algorithm, os, strutils, tables]

const Top = 20

proc main() =
  let text = readFile(paramStr(1))

  var counts = initCountTable[string]()
  var total = 0
  for word in text.splitWhitespace():
    counts.inc(word)
    inc total

  var ranked = newSeqOfCap[(string, int)](counts.len)
  for word, count in counts.pairs:
    ranked.add((word, count))
  ranked.sort(proc(a, b: (string, int)): int =
    result = cmp(b[1], a[1])
    if result == 0:
      result = cmp(a[0], b[0]))

  var output = "total " & $total & "\n"
  output.add("distinct " & $counts.len & "\n")
  for i in 0 ..< min(Top, ranked.len):
    let (word, count) = ranked[i]
    output.add($count & " " & word & "\n")
  stdout.write(output)

main()
