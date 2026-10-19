# ping_pong: two OS threads exchange `n` messages over two one-slot channels.

import std/[os, strutils, typedthreads]

type
  Links = object
    n: int
    ping, pong: ptr Channel[int]

proc newChannel(): ptr Channel[int] =
  ## A channel in shared memory that holds at most one message.
  result = cast[ptr Channel[int]](allocShared0(sizeof(Channel[int])))
  result[].open(maxItems = 1)

proc echoTask(links: Links) {.thread.} =
  ## Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
  for _ in 1 .. links.n:
    let x = links.ping[].recv()
    links.pong[].send(x + 1)

proc main() =
  let n = parseInt(paramStr(1))
  let ping = newChannel()
  let pong = newChannel()
  var b: Thread[Links]
  createThread(b, echoTask, Links(n: n, ping: ping, pong: pong))

  var sum = 0
  for i in 1 .. n:
    ping[].send(i)
    sum += pong[].recv()
  joinThread(b)

  ping[].close()
  pong[].close()
  deallocShared(ping)
  deallocShared(pong)

  stdout.writeLine(n)
  stdout.writeLine(sum)

main()
