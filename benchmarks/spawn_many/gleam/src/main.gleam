//// spawn_many: spawns n short processes in batches of 1000, joins each batch through a
//// fresh subject, and prints the sum of the results.

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list

const batch = 1000

const rounds = 10

const modulus = 2_147_483_647

const multiplier = 48_271

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

pub fn main() -> Nil {
  // The run command calls main from erl's -eval process, which traps exits. Gleam's own
  // entry wrapper (main@@main:run) turns trapping off before it calls main, so do the same:
  // otherwise every linked task's normal exit lands in the mailbox as an 'EXIT' message,
  // and each receive below scans past all of them.
  process.trap_exits(False)
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)
  let sum = batches(0, n, 0)
  io.println("tasks: " <> int.to_string(n) <> "\nsum: " <> int.to_string(sum))
}

/// The value of the task with this index: `rounds` MINSTD steps from index + 1.
fn work(index: Int) -> Int {
  steps(rounds, index + 1)
}

fn steps(k: Int, x: Int) -> Int {
  case k {
    0 -> x
    _ -> steps(k - 1, x * multiplier % modulus)
  }
}

fn batches(start: Int, n: Int, sum: Int) -> Int {
  case start < n {
    False -> sum
    True -> {
      let batch_sum = spawn_and_join(start, int.min(batch, n - start))
      batches(start + batch, n, sum + batch_sum)
    }
  }
}

/// Spawns one process per index in start..start + count - 1, each sending its result to
/// this batch's own subject, then receives every result.
fn spawn_and_join(start: Int, count: Int) -> Int {
  let results = process.new_subject()
  spawn_all(start, start + count, results)
  join(count, results, 0)
}

fn spawn_all(i: Int, end: Int, results: Subject(Int)) -> Nil {
  case i < end {
    False -> Nil
    True -> {
      process.spawn(fn() { process.send(results, work(i)) })
      spawn_all(i + 1, end, results)
    }
  }
}

fn join(k: Int, results: Subject(Int), sum: Int) -> Int {
  case k {
    0 -> sum
    _ -> join(k - 1, results, sum + process.receive_forever(results))
  }
}
