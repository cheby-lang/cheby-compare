# prime_sieve: the concurrent prime sieve, one thread per stage, connected by SizedQueues of size 1.

# Sends 2, 3, 4 and so on, blocking until the next stage takes each one.
def generate(out)
  i = 2
  loop do
    out.push(i)
    i += 1
  end
end

# Passes on the numbers from inp that prime does not divide.
def filter(inp, out, prime)
  loop do
    m = inp.pop
    out.push(m) if m % prime != 0
  end
end

n = Integer(ARGV[0])
# SizedQueue has no capacity 0, so every channel has capacity 1 (SPEC).
ch = SizedQueue.new(1)
Thread.new { generate(ch) }
last = 0
sum = 0
n.times do
  prime = ch.pop
  last = prime
  sum += prime
  nxt = SizedQueue.new(1)
  inp = ch
  Thread.new { filter(inp, nxt, prime) }
  ch = nxt
end
puts "primes: #{n}"
puts "last: #{last}"
puts "sum: #{sum}"
# Shut down (SPEC option 1): the main thread ends and the process kills the blocked threads.
