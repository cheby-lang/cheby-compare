// ping_pong: two tasks on the main actor exchange `n` messages over two AsyncStreams.

/// Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
@MainActor
func echo(_ n: Int, _ ping: AsyncStream<Int>, _ pong: AsyncStream<Int>.Continuation) async {
  var values = ping.makeAsyncIterator()
  for _ in 0..<n {
    let x = await values.next()!
    pong.yield(x + 1)
  }
}

/// Task A: sends 1 through `n` on `ping` and adds up the answers from `pong`.
@MainActor
func play(_ n: Int, _ ping: AsyncStream<Int>.Continuation, _ pong: AsyncStream<Int>) async -> Int {
  var answers = pong.makeAsyncIterator()
  var sum = 0
  for i in stride(from: 1, through: n, by: 1) {
    ping.yield(i)
    sum += await answers.next()!
  }
  return sum
}

let n = Int(CommandLine.arguments[1])!
let (ping, pingIn) = AsyncStream.makeStream(of: Int.self)
let (pong, pongIn) = AsyncStream.makeStream(of: Int.self)

// Top-level code runs on the main actor, and `Task { }` inherits it, so A and B take turns there.
let b = Task { await echo(n, ping, pongIn) }
let sum = await play(n, pingIn, pong)
await b.value
pingIn.finish()
pongIn.finish()

print(n)
print(sum)
