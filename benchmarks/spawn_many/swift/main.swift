// spawn_many: spawn `n` short tasks in batches of 1,000, join each batch and print the sum.
// Each task is a child task of one TaskGroup per batch.

let batch = 1_000
let rounds = 10
let modulus = 2_147_483_647
let multiplier = 48_271

/// The value of the task with this index: `rounds` steps of the MINSTD generator from `index + 1`.
func work(_ index: Int) -> Int {
  var x = index + 1
  for _ in 0..<rounds {
    x = x * multiplier % modulus
  }
  return x
}

/// Spawns one task per index in `start..<start + count`, joins them all and returns their sum.
func spawnAndJoin(_ start: Int, _ count: Int) async -> Int {
  await withTaskGroup(of: Int.self) { group in
    for index in start..<start + count {
      group.addTask { work(index) }
    }
    var sum = 0
    for await value in group {
      sum += value
    }
    return sum
  }
}

let n = Int(CommandLine.arguments[1])!
var sum = 0
var start = 0
while start < n {
  sum += await spawnAndJoin(start, min(batch, n - start))
  start += batch
}
print("tasks: \(n)")
print("sum: \(sum)")
