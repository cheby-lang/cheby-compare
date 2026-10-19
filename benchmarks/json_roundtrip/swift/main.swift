// json_roundtrip: parses a JSON array of records, transforms it and serializes it again.
//
// Parsing is Foundation's JSONDecoder into Decodable structs. JSONEncoder does not keep the
// declared key order (it writes keys in a different order on every run), so the output is
// written by a small hand-written compact serializer that follows the declared order.

import Foundation

let fnvOffset: UInt32 = 2_166_136_261
let fnvPrime: UInt32 = 16_777_619

struct Address: Decodable {
  let street: String
  let city: String
  let zip: Int
}

struct Entry: Decodable {
  let day: Int
  let amount: Int
}

struct Record: Decodable {
  let id: Int
  let name: String
  let active: Bool
  let score: Int
  let tags: [String]
  let address: Address
  let history: [Entry]
}

/// A kept record as it is written: `active` is gone, `score` changed and `total` added.
struct Output {
  let id: Int
  let name: String
  let score: Int
  let tags: [String]
  let address: Address
  let history: [Entry]
  let total: Int
}

// MARK: - Compact JSON writer

protocol JSONWritable {
  func writeJSON(to out: inout String)
}

extension Int: JSONWritable {
  func writeJSON(to out: inout String) { out += String(self) }
}

extension String: JSONWritable {
  func writeJSON(to out: inout String) {
    out += "\""
    if utf8.allSatisfy({ $0 >= 0x20 && $0 != UInt8(ascii: "\"") && $0 != UInt8(ascii: "\\") }) {
      out += self
    } else {
      for scalar in unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        case let c where c.value < 0x20:
          out += c.value < 0x10 ? "\\u000" : "\\u00"
          out += String(c.value, radix: 16)
        default: out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
  }
}

extension Array: JSONWritable where Element: JSONWritable {
  func writeJSON(to out: inout String) {
    out += "["
    for (i, element) in enumerated() {
      if i > 0 { out += "," }
      element.writeJSON(to: &out)
    }
    out += "]"
  }
}

// Objects are written field by field, with the keys in the order the SPEC fixes.

extension Address: JSONWritable {
  func writeJSON(to out: inout String) {
    out += "{\"street\":"
    street.writeJSON(to: &out)
    out += ",\"city\":"
    city.writeJSON(to: &out)
    out += ",\"zip\":"
    zip.writeJSON(to: &out)
    out += "}"
  }
}

extension Entry: JSONWritable {
  func writeJSON(to out: inout String) {
    out += "{\"day\":"
    day.writeJSON(to: &out)
    out += ",\"amount\":"
    amount.writeJSON(to: &out)
    out += "}"
  }
}

extension Output: JSONWritable {
  func writeJSON(to out: inout String) {
    out += "{\"id\":"
    id.writeJSON(to: &out)
    out += ",\"name\":"
    name.writeJSON(to: &out)
    out += ",\"score\":"
    score.writeJSON(to: &out)
    out += ",\"tags\":"
    tags.writeJSON(to: &out)
    out += ",\"address\":"
    address.writeJSON(to: &out)
    out += ",\"history\":"
    history.writeJSON(to: &out)
    out += ",\"total\":"
    total.writeJSON(to: &out)
    out += "}"
  }
}

func serialize<T: JSONWritable>(_ value: T) -> String {
  var out = ""
  value.writeJSON(to: &out)
  return out
}

// MARK: - Benchmark

func fnv1a(_ hash: UInt32, _ bytes: String.UTF8View) -> UInt32 {
  bytes.reduce(hash) { h, b in (h ^ UInt32(b)) &* fnvPrime }
}

func roundtrip(path: String, reps: Int) throws -> String {
  let text = try Data(contentsOf: URL(fileURLWithPath: path))
  let decoder = JSONDecoder()

  var recordsN = 0
  var activeN = 0
  var scoreSum = 0
  var tagsN = 0
  var historyN = 0
  var amountSum = 0
  var outputBytes = 0
  var hash = fnvOffset
  for rep in 0..<reps {
    let records = try decoder.decode([Record].self, from: text)
    var kept: [Output] = []
    for r in records {
      let total = r.history.reduce(0) { $0 + $1.amount }
      recordsN += 1
      scoreSum += r.score
      tagsN += r.tags.count
      historyN += r.history.count
      amountSum += total
      if r.active {
        activeN += 1
        kept.append(
          Output(
            id: r.id,
            name: r.name,
            score: r.score + 100 * r.tags.count,
            tags: r.tags,
            address: r.address,
            history: r.history,
            total: total
          ))
      }
    }
    let out = serialize(kept)
    outputBytes += out.utf8.count
    if rep == reps - 1 {
      hash = fnv1a(fnvOffset, out.utf8)
    }
  }

  return """
    records \(recordsN)
    active \(activeN)
    score_sum \(scoreSum)
    tags \(tagsN)
    history \(historyN)
    amount_sum \(amountSum)
    output_bytes \(outputBytes)
    output_fnv1a \(hash)
    """
}

print(try roundtrip(path: CommandLine.arguments[1], reps: Int(CommandLine.arguments[2])!))
