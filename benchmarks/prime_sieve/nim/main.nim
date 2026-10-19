# prime_sieve: the concurrent prime sieve, one OS thread per stage, connected by one-slot
# channels in shared memory.

import std/[os, strutils, typedthreads]

type
  Chan = ptr Channel[int]
  Stage = tuple[input, output: Chan, prime: int]

proc newChan(): Chan =
  ## A channel in shared memory that holds at most one message.
  result = cast[Chan](allocShared0(sizeof(Channel[int])))
  result[].open(maxItems = 1)

proc generate(output: Chan) {.thread.} =
  ## Sends 2, 3, 4 and so on, forever.
  var i = 2
  while true:
    output[].send(i)
    inc i

proc filter(stage: Stage) {.thread.} =
  ## Passes on the numbers from `input` that `prime` does not divide, forever.
  while true:
    let m = stage.input[].recv()
    if m mod stage.prime != 0:
      stage.output[].send(m)

proc main() =
  let n = parseInt(paramStr(1))
  # A running thread must not move, so every thread object is allocated up front.
  var generator: Thread[Chan]
  var filters = newSeq[Thread[Stage]](n)

  var ch = newChan()
  createThread(generator, generate, ch)
  var last = 0
  var sum = 0
  for k in 0 ..< n:
    let prime = ch[].recv()
    last = prime
    sum += prime
    let next = newChan()
    createThread(filters[k], filter, (input: ch, output: next, prime: prime))
    ch = next

  stdout.writeLine("primes: ", n)
  stdout.writeLine("last: ", last)
  stdout.writeLine("sum: ", sum)
  # A recv that is already blocked does not wake when its channel is closed, so
  # end the process with the stages still blocked (SPEC, "Shut down", option 1).
  # quit flushes stdout.
  quit(0)

main()
