// word_freq: counts the words of a file and prints the 20 most frequent.

import Foundation

let top = 20

func wordFreq(path: String) -> String {
  let bytes = [UInt8](FileManager.default.contents(atPath: path)!)

  var counts: [String: Int] = [:]
  var total = 0
  for word in bytes.split(whereSeparator: { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\n") }) {
    counts[String(decoding: word, as: UTF8.self), default: 0] += 1
    total += 1
  }

  let ranked = counts.sorted { a, b in
    a.value != b.value ? a.value > b.value : a.key < b.key
  }

  var out = "total \(total)\ndistinct \(counts.count)"
  for (word, count) in ranked.prefix(top) {
    out += "\n\(count) \(word)"
  }
  return out
}

print(wordFreq(path: CommandLine.arguments[1]))
