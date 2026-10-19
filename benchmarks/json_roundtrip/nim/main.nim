# json_roundtrip: parses a JSON array of records, transforms it and serializes it again.

import std/[json, os, strutils]

const
  FnvOffset = 2166136261'u32
  FnvPrime = 16777619'u32

type
  Address = object
    street: string
    city: string
    zip: int

  Entry = object
    day: int
    amount: int

  Record = object
    id: int
    name: string
    active: bool
    score: int
    tags: seq[string]
    address: Address
    history: seq[Entry]

  Output = object
    id: int
    name: string
    score: int
    tags: seq[string]
    address: Address
    history: seq[Entry]
    total: int

proc fnv1a(h: uint32, data: string): uint32 =
  result = h
  for c in data:
    result = (result xor uint32(c)) * FnvPrime

proc main() =
  let text = readFile(paramStr(1))
  let reps = parseInt(paramStr(2))

  var recordsN, activeN, scoreSum, tagsN, historyN, amountSum, outputBytes: int64
  var h = FnvOffset
  for rep in 0 ..< reps:
    let records = parseJson(text).to(seq[Record])
    var kept: seq[Output]
    for r in records:
      var total = 0
      for e in r.history:
        total += e.amount
      inc recordsN
      scoreSum += r.score
      tagsN += r.tags.len
      historyN += r.history.len
      amountSum += total
      if r.active:
        inc activeN
        kept.add(Output(
          id: r.id,
          name: r.name,
          score: r.score + 100 * r.tags.len,
          tags: r.tags,
          address: r.address,
          history: r.history,
          total: total,
        ))
    let output = $(%kept)
    outputBytes += output.len
    if rep == reps - 1:
      h = fnv1a(FnvOffset, output)

  stdout.write(
    "records " & $recordsN & "\n" &
    "active " & $activeN & "\n" &
    "score_sum " & $scoreSum & "\n" &
    "tags " & $tagsN & "\n" &
    "history " & $historyN & "\n" &
    "amount_sum " & $amountSum & "\n" &
    "output_bytes " & $outputBytes & "\n" &
    "output_fnv1a " & $h & "\n")

main()
