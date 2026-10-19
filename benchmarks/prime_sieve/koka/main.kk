// prime_sieve: the concurrent prime sieve on std/async strands. A generator strand answers
// requests with 2, 3, 4 and so on, and each prime that comes out of the pipeline adds a filter
// strand to its end. After n primes the program prints n, the n-th prime and the sum of the
// first n primes.
//
// A std/async `emit` never blocks, so the stages use the SPEC's pull protocol: a stage asks the
// one before it for every number. Each stage owns a request channel, and a request carries the
// requester's own reply channel (its inbox), which the requester creates once.
//
// std/async spawns strands only through `interleaved` and `firstof`, which take their strands
// up front. So each new filter is started by a nested `firstof` of the filter and the rest of
// the sieve. When the sieve returns, every `firstof` on the way out cancels its filter, and the
// outermost one cancels the generator (SPEC "Shut down", option 2).
import std/async
import std/os/env

// A stage's request channel: each request is the reply channel to send one number to.
alias requests = channel<channel<int>>

// Answers each request with the next integer, from `i` upward.
fun generator(reqs : requests, i : int) : <async,ndet,div> a
  val reply = reqs.receive
  reply.emit(i)
  generator(reqs, i + 1)

// Answers each request with the next number from `up` that `prime` does not divide.
fun filter(prime : int, up : requests, reqs : requests, inbox : channel<int>) : <async,ndet,div> a
  val reply = reqs.receive
  reply.emit(pull(prime, up, inbox))
  filter(prime, up, reqs, inbox)

// Asks `up` for numbers until one arrives that `prime` does not divide.
fun pull(prime : int, up : requests, inbox : channel<int>) : <async,ndet,div> int
  up.emit(inbox)
  val m = inbox.receive
  if m % prime == 0 then pull(prime, up, inbox) else m

// Takes the next `remaining` primes from the stage `cur`, starting a filter after each one, and
// returns the last prime and the sum of all primes taken.
fun sieve(remaining : int, cur : requests, inbox : channel<int>, last : int, sum : int) : <async,ndet,div> (int, int)
  if remaining == 0 then (last, sum)
  else
    cur.emit(inbox)
    val prime = inbox.receive
    val next = channel()
    val filter-inbox = channel()
    firstof({ filter(prime, cur, next, filter-inbox) }, { sieve(remaining - 1, next, inbox, prime, sum + prime) })

pub fun main()
  val n = get-args().head.default("0").parse-int.default(0)
  async
    val numbers = channel()
    val inbox = channel()
    val (last, sum) = firstof({ generator(numbers, 2) }, { sieve(n, numbers, inbox, 0, 0) })
    println("primes: " ++ n.show)
    println("last: " ++ last.show)
    println("sum: " ++ sum.show)
