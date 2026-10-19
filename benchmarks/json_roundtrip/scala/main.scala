//> using dep com.lihaoyi::ujson:4.4.3
// json_roundtrip: parses an array of records with ujson, aggregates and transforms them, and
// writes the kept records back as compact JSON, `reps` times.

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}
import scala.collection.mutable.ArrayBuffer

val FnvOffset = 2166136261L
val FnvPrime = 16777619L

@main def main(path: String, reps: Int): Unit =
  val text = Files.readString(Path.of(path), StandardCharsets.US_ASCII)
  var recordsN, activeN, scoreSum, tagsN, historyN, amountSum, outputBytes = 0L
  var h = FnvOffset

  for rep <- 0 until reps do
    val records = ujson.read(text).arr
    val kept = ArrayBuffer.empty[ujson.Value]
    for r <- records do
      val score = r("score").num.toLong
      val tags = r("tags").arr
      val history = r("history").arr
      val total = history.iterator.map(_("amount").num.toLong).sum
      recordsN += 1
      scoreSum += score
      tagsN += tags.length
      historyN += history.length
      amountSum += total
      if r("active").bool then
        activeN += 1
        kept += ujson.Obj(
          "id" -> r("id"),
          "name" -> r("name"),
          "score" -> ujson.Num((score + 100 * tags.length).toDouble),
          "tags" -> tags,
          "address" -> r("address"), // ujson.Obj keeps the key order street, city, zip
          "history" -> history,
          "total" -> ujson.Num(total.toDouble),
        )
    val out = ujson.write(ujson.Arr(kept))
    outputBytes += out.length // ASCII: one byte per char
    if rep == reps - 1 then
      var i = 0
      while i < out.length do
        h = ((h ^ out.charAt(i)) * FnvPrime) & 0xFFFFFFFFL
        i += 1

  print(
    s"records $recordsN\nactive $activeN\nscore_sum $scoreSum\ntags $tagsN\nhistory $historyN\n" +
      s"amount_sum $amountSum\noutput_bytes $outputBytes\noutput_fnv1a $h\n"
  )
