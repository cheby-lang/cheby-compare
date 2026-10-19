// ping_pong: two std/async strands pass a number back and forth n times over two channels,
// then print n and the sum of the answers.
import std/async
import std/os/env

// Task B: answers each of the n values from `ping` with the value plus one on `pong`.
fun echo(n : int, ping : channel<int>, pong : channel<int>) : <async,ndet,div> ()
  for(1, n) fn(_)
    val x = ping.receive
    pong.emit(x + 1)

// Task A: sends 1 to n on `ping` and sums the answers from `pong`.
fun play(n : int, ping : channel<int>, pong : channel<int>) : <async,ndet,div> int
  var sum := 0
  for(1, n) fn(i)
    ping.emit(i)
    sum := sum + pong.receive
  sum

pub fun main()
  val n = get-args().head.default("0").parse-int.default(0)
  async
    val ping = channel()
    val pong = channel()
    // Both tasks are strands of one interleaving, which returns when both have ended.
    val (sum, _) = interleaved({ play(n, ping, pong) }, { echo(n, ping, pong) })
    println(n.show)
    println(sum.show)
