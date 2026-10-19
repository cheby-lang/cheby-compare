//// Fannkuch-redux: counts pancake flips over every permutation of 0..n-1, as lists.

import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

type State {
  State(n: Int, max_flips: Int, checksum: Int, perm_index: Int)
}

/// `xs` with the element at index `i` replaced by `value`.
fn set_at(xs: List(Int), i: Int, value: Int) -> List(Int) {
  case xs, i {
    [_, ..rest], 0 -> [value, ..rest]
    [x, ..rest], _ -> [x, ..set_at(rest, i - 1, value)]
    [], _ -> []
  }
}

/// `xs` with the element at index `i` decremented, and the new value.
fn decrement_at(xs: List(Int), i: Int) -> #(List(Int), Int) {
  case xs, i {
    [x, ..rest], 0 -> #([x - 1, ..rest], x - 1)
    [x, ..rest], _ -> {
      let #(rest, value) = decrement_at(rest, i - 1)
      #([x, ..rest], value)
    }
    [], _ -> #([], 0)
  }
}

/// Step 1: count[r - 1] = r, while r != 1.
fn reset(r: Int, count: List(Int)) -> List(Int) {
  case r {
    1 -> count
    _ -> reset(r - 1, set_at(count, r - 1, r))
  }
}

/// Step 2: reverse the first k + 1 elements until 0 is in front.
fn count_flips(perm: List(Int), flips: Int) -> Int {
  case perm {
    [0, ..] | [] -> flips
    [k, ..] -> {
      let #(front, back) = list.split(perm, k + 1)
      count_flips(list.append(list.reverse(front), back), flips + 1)
    }
  }
}

/// Steps 1 and 2 for the current permutation, then step 3.
fn visit(perm1: List(Int), count: List(Int), r: Int, state: State) -> State {
  let count = reset(r, count)
  let flips = count_flips(perm1, 0)
  let State(n, max_flips, checksum, perm_index) = state
  let checksum = case perm_index % 2 {
    0 -> checksum + flips
    _ -> checksum - flips
  }
  next(
    perm1,
    count,
    1,
    State(n, int.max(max_flips, flips), checksum, perm_index),
  )
}

/// Step 3: rotate the first r + 1 elements left by one and step the counters.
fn next(perm1: List(Int), count: List(Int), r: Int, state: State) -> State {
  case r == state.n {
    True -> state
    False -> {
      let assert #([first, ..rest], back) = list.split(perm1, r + 1)
      let perm1 = list.append(rest, [first, ..back])
      let #(count, c) = decrement_at(count, r)
      case c > 0 {
        True ->
          visit(
            perm1,
            count,
            r,
            State(..state, perm_index: state.perm_index + 1),
          )
        False -> next(perm1, count, r + 1, state)
      }
    }
  }
}

fn fannkuch(n: Int) -> #(Int, Int) {
  let perm1 = int.range(from: n - 1, to: -1, with: [], run: list.prepend)
  let count = list.repeat(0, n)
  let State(_, max_flips, checksum, _) =
    visit(perm1, count, n, State(n, 0, 0, 0))
  #(checksum, max_flips)
}

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)

  let #(checksum, max_flips) = fannkuch(int.max(n, 1))
  io.println(int.to_string(checksum))
  io.println(
    "Pfannkuchen(" <> int.to_string(n) <> ") = " <> int.to_string(max_flips),
  )
}
