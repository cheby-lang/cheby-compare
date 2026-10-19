# ping_pong: two threads pass a number back and forth n times over two SizedQueues of size 1.

# Task B: answers each number on ping with that number plus one on pong, exactly n times.
def echo(n, ping, pong)
  n.times do
    x = ping.pop
    pong.push(x + 1)
  end
end

# Task A: sends 1..n on ping and adds up the answers from pong.
def play(n, ping, pong)
  sum = 0
  (1..n).each do |i|
    ping.push(i)
    sum += pong.pop
  end
  sum
end

n = Integer(ARGV[0])
# SizedQueue has no capacity 0, so capacity 1 (SPEC): only one message is ever in flight.
ping = SizedQueue.new(1)
pong = SizedQueue.new(1)
b = Thread.new { echo(n, ping, pong) }
sum = play(n, ping, pong)
b.join
puts n
puts sum
