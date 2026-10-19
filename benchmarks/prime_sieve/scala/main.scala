// prime_sieve: the concurrent prime sieve, one virtual thread per stage, connected by rendezvous
// channels. Prints n, the n-th prime and the sum of the first n primes.
import java.util.concurrent.SynchronousQueue

/** Sends 2, 3, 4 and so on to `out`, forever. */
def generate(out: SynchronousQueue[Long]): Unit =
  var i = 2L
  while true do
    out.put(i)
    i += 1

/** Passes on the numbers from `in` that `prime` does not divide, forever. */
def filter(in: SynchronousQueue[Long], out: SynchronousQueue[Long], prime: Long): Unit =
  while true do
    val m = in.take()
    if m % prime != 0 then out.put(m)

@main def main(n: Int): Unit =
  var ch = SynchronousQueue[Long]()
  val first = ch
  Thread.ofVirtual().start(() => generate(first))
  var last = 0L
  var sum = 0L
  for _ <- 0 until n do
    val prime = ch.take()
    last = prime
    sum += prime
    val in = ch
    val next = SynchronousQueue[Long]()
    Thread.ofVirtual().start(() => filter(in, next, prime))
    ch = next

  // Virtual threads are daemon threads: returning from main ends the JVM with every stage still
  // blocked (SPEC, "Shut down", option 1).
  println(s"primes: $n")
  println(s"last: $last")
  println(s"sum: $sum")
