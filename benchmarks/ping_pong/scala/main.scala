// ping_pong: two virtual threads exchange `n` messages over two rendezvous channels.
import java.util.concurrent.{FutureTask, SynchronousQueue}

/** Task B: answers each of the `n` values from `ping` with the value plus one on `pong`. */
def echo(n: Long, ping: SynchronousQueue[Long], pong: SynchronousQueue[Long]): Unit =
  var r = 0L
  while r < n do
    val x = ping.take()
    pong.put(x + 1)
    r += 1

/** Task A: sends 1..n on `ping` and adds up the answers from `pong`. */
def play(n: Long, ping: SynchronousQueue[Long], pong: SynchronousQueue[Long]): Long =
  var sum = 0L
  var i = 1L
  while i <= n do
    ping.put(i)
    sum += pong.take()
    i += 1
  sum

@main def main(n: Long): Unit =
  val ping = SynchronousQueue[Long]()
  val pong = SynchronousQueue[Long]()

  // The JVM main thread is a platform thread, so A runs on a virtual thread like B.
  val b = Thread.ofVirtual().start(() => echo(n, ping, pong))
  val playTask = FutureTask[Long](() => play(n, ping, pong))
  val a = Thread.ofVirtual().start(playTask)
  a.join()
  val sum = playTask.get()
  b.join()

  println(n)
  println(sum)
