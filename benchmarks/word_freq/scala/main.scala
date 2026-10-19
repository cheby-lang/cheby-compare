// word_freq: counts the words of a file and prints the 20 most frequent.

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}
import scala.collection.mutable

val Top = 20

@main def main(path: String): Unit =
  val text = Files.readString(Path.of(path), StandardCharsets.US_ASCII)

  val counts = mutable.HashMap.empty[String, Int]
  var total = 0L
  for word <- text.split("\\s+") if word.nonEmpty do // skips a leading empty part
    counts.update(word, counts.getOrElse(word, 0) + 1)
    total += 1

  val ranked = counts.toArray.sortWith { case ((wa, ca), (wb, cb)) =>
    if ca != cb then ca > cb else wa < wb
  }

  val out = StringBuilder()
  out ++= s"total $total\n"
  out ++= s"distinct ${counts.size}\n"
  for (word, count) <- ranked.take(Top) do out ++= s"$count $word\n"
  print(out)
