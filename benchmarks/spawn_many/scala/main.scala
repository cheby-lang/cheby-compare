// spawn_many: spawn `n` short Futures in batches of 1000, join each batch and print the sum.
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.concurrent.duration.Duration

given ExecutionContext = ExecutionContext.global

val Batch = 1000L
val Rounds = 10
val Modulus = 2147483647L // 2^31 - 1
val Multiplier = 48271L // the MINSTD generator

/** The value of the task with this index: `Rounds` steps of MINSTD from `index + 1`. */
def work(index: Long): Long =
  var x = index + 1
  var r = 0
  while r < Rounds do
    x = x * Multiplier % Modulus
    r += 1
  x

/** Starts one Future per index in `start until start + count`, joins them all, returns the sum. */
def spawnAndJoin(start: Long, count: Long): Long =
  val batch = (start until start + count).map(i => Future(work(i)))
  Await.result(Future.sequence(batch), Duration.Inf).sum

@main def main(n: Long): Unit =
  var sum = 0L
  var start = 0L
  while start < n do
    sum += spawnAndJoin(start, math.min(Batch, n - start))
    start += Batch
  println(s"tasks: $n")
  println(s"sum: $sum")
