//// ping_pong: two processes pass a number back and forth n times over two subjects.
//// Prints n and the sum of the replies.

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)

  // A subject can only be received by the process that created it, so B creates `ping`
  // and hands it to A over `setup`, once, before the first round.
  let setup: Subject(Subject(Int)) = process.new_subject()
  let pong: Subject(Int) = process.new_subject()
  process.spawn(fn() {
    let ping = process.new_subject()
    process.send(setup, ping)
    echo_loop(n, ping, pong)
  })
  let ping = process.receive_forever(setup)

  let sum = play(1, n, ping, pong, 0)
  // B ends right after its last reply; A does not wait further (SPEC, "Join").
  io.println(int.to_string(n) <> "\n" <> int.to_string(sum))
}

/// Task B: answers each value from `ping` with the value plus one on `pong`, exactly n times.
fn echo_loop(n: Int, ping: Subject(Int), pong: Subject(Int)) -> Nil {
  case n {
    0 -> Nil
    _ -> {
      let x = process.receive_forever(ping)
      process.send(pong, x + 1)
      echo_loop(n - 1, ping, pong)
    }
  }
}

/// Task A: sends i = 1..n on `ping` and adds up the answers from `pong`.
fn play(
  i: Int,
  n: Int,
  ping: Subject(Int),
  pong: Subject(Int),
  sum: Int,
) -> Int {
  case i > n {
    True -> sum
    False -> {
      process.send(ping, i)
      let x = process.receive_forever(pong)
      play(i + 1, n, ping, pong, sum + x)
    }
  }
}
