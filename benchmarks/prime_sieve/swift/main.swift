// prime_sieve: the concurrent prime sieve, one task per stage, linked by rendezvous actor channels.

/// A rendezvous channel: a send waits until a receiver takes its value. It holds the waiting
/// receivers and the waiting senders with their values, and never a buffered value.
actor Channel {
  private var receivers: [CheckedContinuation<Int, Never>] = []
  private var senders: [(value: Int, taken: CheckedContinuation<Void, Never>)] = []

  func send(_ value: Int) async {
    if !receivers.isEmpty {
      receivers.removeFirst().resume(returning: value)
      return
    }
    await withCheckedContinuation { senders.append((value, $0)) }
  }

  func receive() async -> Int {
    if !senders.isEmpty {
      let sender = senders.removeFirst()
      sender.taken.resume()
      return sender.value
    }
    return await withCheckedContinuation { receivers.append($0) }
  }
}

/// Sends 2, 3, 4 and so on, forever.
func generate(_ out: Channel) async {
  var i = 2
  while true {
    await out.send(i)
    i += 1
  }
}

/// Passes on the numbers from `input` that `prime` does not divide, forever.
func filter(_ input: Channel, _ out: Channel, _ prime: Int) async {
  while true {
    let m = await input.receive()
    if m % prime != 0 {
      await out.send(m)
    }
  }
}

let n = Int(CommandLine.arguments[1])!
var ch = Channel()
let first = ch
Task { await generate(first) }
var last = 0
var sum = 0
for _ in 0..<n {
  let prime = await ch.receive()
  last = prime
  sum += prime
  let input = ch
  let next = Channel()
  Task { await filter(input, next, prime) }
  ch = next
}

// Shut down (SPEC option 1): print and end the process with every stage still suspended.
print("primes: \(n)")
print("last: \(last)")
print("sum: \(sum)")
