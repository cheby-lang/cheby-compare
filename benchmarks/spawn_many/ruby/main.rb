# spawn_many: spawns one thread per index in batches of 1,000, joins each batch and sums the results.

B = 1000
ROUNDS = 10
MODULUS = 2_147_483_647 # 2^31 - 1
MULTIPLIER = 48_271 # the MINSTD generator

# Ten MINSTD steps from index + 1; runs inside the thread.
def work(index)
  x = index + 1
  ROUNDS.times { x = (x * MULTIPLIER) % MODULUS }
  x
end

# Spawns every thread of one batch, then joins them all and returns the sum of their values.
def spawn_and_join(start, count)
  threads = Array.new(count) { |j| Thread.new(start + j) { |index| work(index) } }
  threads.sum(&:value)
end

n = Integer(ARGV[0])
sum = 0
start = 0
while start < n
  sum += spawn_and_join(start, [B, n - start].min)
  start += B
end
puts "tasks: #{n}"
puts "sum: #{sum}"
