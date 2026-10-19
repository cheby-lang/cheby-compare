//// prime_sieve: the concurrent prime sieve. A generator process and one filter process per
//// prime, connected by the pull protocol: each stage asks the one before it for every number.

import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list

/// A request for the next number, answered on `reply_to`.
type Next {
  Next(reply_to: Subject(Int))
}

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)

  // Each stage creates its request subject and hands it to main over `setup`.
  let setup: Subject(Subject(Next)) = process.new_subject()
  let numbers: Subject(Int) = process.new_subject()
  process.spawn(fn() {
    let requests = process.new_subject()
    process.send(setup, requests)
    generator(2, requests)
  })
  let gen = process.receive_forever(setup)
  let #(last, sum) = primes(n, gen, setup, numbers, 0, 0)
  // The stages stay blocked in receive; the halt(0) after main ends them (SPEC "Shut down",
  // option 1).
  io.println(
    "primes: "
    <> int.to_string(n)
    <> "\nlast: "
    <> int.to_string(last)
    <> "\nsum: "
    <> int.to_string(sum),
  )
}

/// Receives k primes from the end of the pipeline, spawning a filter after each one.
fn primes(
  k: Int,
  cur: Subject(Next),
  setup: Subject(Subject(Next)),
  numbers: Subject(Int),
  last: Int,
  sum: Int,
) -> #(Int, Int) {
  case k {
    0 -> #(last, sum)
    _ -> {
      process.send(cur, Next(numbers))
      let p = process.receive_forever(numbers)
      process.spawn(fn() {
        let requests = process.new_subject()
        process.send(setup, requests)
        filter(p, cur, requests, process.new_subject())
      })
      let next = process.receive_forever(setup)
      primes(k - 1, next, setup, numbers, p, sum + p)
    }
  }
}

/// Answers each request with the next integer, from 2 upward.
fn generator(i: Int, requests: Subject(Next)) -> Nil {
  let Next(reply_to) = process.receive_forever(requests)
  process.send(reply_to, i)
  generator(i + 1, requests)
}

/// Answers each request with the next number from `up` that `prime` does not divide.
/// `requests` and `numbers` are this filter's own subjects, created once at its start.
fn filter(
  prime: Int,
  up: Subject(Next),
  requests: Subject(Next),
  numbers: Subject(Int),
) -> Nil {
  let Next(reply_to) = process.receive_forever(requests)
  process.send(reply_to, pull(prime, up, numbers))
  filter(prime, up, requests, numbers)
}

fn pull(prime: Int, up: Subject(Next), numbers: Subject(Int)) -> Int {
  process.send(up, Next(numbers))
  let m = process.receive_forever(numbers)
  case m % prime {
    0 -> pull(prime, up, numbers)
    _ -> m
  }
}
