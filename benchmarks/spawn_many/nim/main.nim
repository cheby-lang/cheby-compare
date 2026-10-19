# spawn_many: spawn `n` short tasks in batches of `Batch`, join each batch and print the sum.
# Each task is one OS thread from createThread; it writes its result to its own slot.

import std/[os, strutils, typedthreads]

const
  Batch = 1000
  Rounds = 10
  Modulus = 2147483647
  Multiplier = 48271

proc work(index: int): int =
  ## The value of the task with this index: `Rounds` steps of the MINSTD generator from `index + 1`.
  var x = index + 1
  for _ in 1 .. Rounds:
    x = x * Multiplier mod Modulus
  x

proc task(job: tuple[index: int, slot: ptr int]) {.thread.} =
  job.slot[] = work(job.index)

proc spawnAndJoin(start, count: int): int =
  ## Spawns one thread per index in `start ..< start + count`, joins them all and returns their sum.
  var threads = newSeq[Thread[tuple[index: int, slot: ptr int]]](count)
  var results = newSeq[int](count)
  for j in 0 ..< count:
    createThread(threads[j], task, (index: start + j, slot: addr results[j]))
  joinThreads(threads)
  for r in results:
    result += r

proc main() =
  let n = parseInt(paramStr(1))
  var sum = 0
  var start = 0
  while start < n:
    sum += spawnAndJoin(start, min(Batch, n - start))
    start += Batch
  stdout.writeLine("tasks: ", n)
  stdout.writeLine("sum: ", sum)

main()
