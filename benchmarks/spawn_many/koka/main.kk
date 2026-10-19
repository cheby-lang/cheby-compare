// spawn_many: spawns n short tasks in batches of 1000 on a small cooperative scheduler, joins
// every batch and prints the sum of the tasks' results.
//
// Koka's standard install has no task primitive with dynamic spawn and join, so the program
// writes its own scheduler as an effect handler: `spawn` queues a suspended task and returns a
// handle, and `join` runs queued tasks in order until that handle's result is ready.
import std/os/env

// How many tasks one batch holds.
val batch = 1000

// How many generator steps one task takes.
val rounds = 10

// The MINSTD modulus, 2^31 - 1.
val modulus = 2147483647

// The MINSTD multiplier.
val multiplier = 48271

// A task's handle: the cell its result is stored in once the task has run.
abstract struct task
  result : ref<global, maybe<int>>

// Spawning and joining tasks.
effect tasks
  // Queues `action` as a new task and returns its handle.
  fun spawn(action : () -> int) : task
  // Runs queued tasks until `t` has finished and returns its result.
  fun join(t : task) : int

// Runs `action` with a FIFO scheduler for its tasks. The queue is a front list and a reversed
// back list.
fun scheduler(action : () -> <tasks,st<global>,div,exn|e> a) : <st<global>,div,exn|e> a
  var front : list<(task, () -> int)> := []
  var back : list<(task, () -> int)> := []
  // Runs the oldest queued task and stores its result in its handle.
  fun run-next()
    match front
      Cons((t, act), rest) ->
        front := rest
        val cell = t.result
        cell := Just(act())
      Nil -> match back
        Nil -> throw("join: no task is queued")
        _ ->
          front := back.reverse
          back := []
  with handler
    fun spawn(act)
      val t = Task(ref(Nothing))
      back := Cons((t, act), back)
      t
    fun join(t)
      fun wait()
        val cell = t.result
        match !cell
          Just(x) -> x
          Nothing ->
            run-next()
            wait()
      wait()
  action()

// The value of the task with this index: `rounds` steps of the MINSTD generator from index + 1.
fun work(index : int) : int
  var x := index + 1
  repeat(rounds)
    x := (x * multiplier) % modulus
  x

// Spawns one task for each index from `start` to `start + count - 1`, then joins them all and
// returns the sum of their results.
fun spawn-and-join(start : int, count : int) : <tasks,div> int
  fun spawn-all(i : int, handles : list<task>) : <tasks,div> list<task>
    if i == count then handles
    else
      val index = start + i
      spawn-all(i + 1, Cons(spawn({ work(index) }), handles))
  spawn-all(0, []).foldl(0) fn(acc, t) acc + join(t)

pub fun main()
  val n = get-args().head.default("0").parse-int.default(0)
  fun run(start : int, total : int) : <tasks,div> int
    if start >= n then total
    else run(start + batch, total + spawn-and-join(start, min(batch, n - start)))
  val sum = with scheduler in run(0, 0)
  println("tasks: " ++ n.show)
  println("sum: " ++ sum.show)
