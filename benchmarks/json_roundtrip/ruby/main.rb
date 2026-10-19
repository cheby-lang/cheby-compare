# json_roundtrip: parses a JSON array of records, transforms it and serializes it again.

require "json"

FNV_OFFSET = 2_166_136_261
FNV_PRIME = 16_777_619
MASK32 = 0xFFFF_FFFF

def fnv1a(h, bytes)
  bytes.each_byte { |b| h = ((h ^ b) * FNV_PRIME) & MASK32 }
  h
end

def transform(record, total)
  {
    "id" => record["id"],
    "name" => record["name"],
    "score" => record["score"] + 100 * record["tags"].length,
    "tags" => record["tags"],
    "address" => record["address"],
    "history" => record["history"],
    "total" => total,
  }
end

path = ARGV[0]
reps = Integer(ARGV[1])
text = File.binread(path)

records_n = active_n = score_sum = tags_n = history_n = amount_sum = output_bytes = 0
h = FNV_OFFSET
reps.times do |rep|
  records = JSON.parse(text)
  kept = []
  records.each do |record|
    history = record["history"]
    total = history.sum { |entry| entry["amount"] }
    records_n += 1
    score_sum += record["score"]
    tags_n += record["tags"].length
    history_n += history.length
    amount_sum += total
    if record["active"]
      active_n += 1
      kept << transform(record, total)
    end
  end
  out = JSON.generate(kept)
  output_bytes += out.bytesize
  h = fnv1a(FNV_OFFSET, out) if rep == reps - 1
end

puts "records #{records_n}"
puts "active #{active_n}"
puts "score_sum #{score_sum}"
puts "tags #{tags_n}"
puts "history #{history_n}"
puts "amount_sum #{amount_sum}"
puts "output_bytes #{output_bytes}"
puts "output_fnv1a #{h}"
