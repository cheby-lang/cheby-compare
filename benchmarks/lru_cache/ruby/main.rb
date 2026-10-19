# lru_cache: a capacity-bounded LRU cache under a skewed pseudo-random key stream.

MODULUS = 1_000_000_007
LEHMER_M = 2_147_483_647
LEHMER_A = 48_271
SEED = 42
HOT_PERCENT = 80
KEY_SPACE_FACTOR = 16

capacity = Integer(ARGV[0])
ops = Integer(ARGV[1])
hot = capacity
cold = capacity * (KEY_SPACE_FACTOR - 1)

# Hash keeps insertion order: the first entry is the least recently used.
cache = {}
hits = 0
misses = 0
values = 0
state = SEED
ops.times do
  state = state * LEHMER_A % LEHMER_M
  draw = state / 100
  key = state % 100 < HOT_PERCENT ? draw % hot : hot + draw % cold
  value = cache.delete(key)
  if value
    cache[key] = value
    hits += 1
    values = (values + value) % MODULUS
  else
    cache.shift if cache.size == capacity
    cache[key] = key * 2 + 1
    misses += 1
  end
end

checksum = 0
cache.each_key.with_index(1) do |key, position|
  checksum = (checksum + position * key) % MODULUS
end

puts "hits #{hits}"
puts "misses #{misses}"
puts "values #{values}"
puts "checksum #{checksum}"
