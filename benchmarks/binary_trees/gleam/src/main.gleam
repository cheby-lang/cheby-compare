//// Binary trees: builds and walks many perfect binary trees, single-threaded.

import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

const min_depth = 4

pub type Tree {
  Empty
  Node(left: Tree, right: Tree)
}

/// A perfect tree of depth `d`: left subtree first, then right. Its leaves are
/// `Node(empty, empty)`. The function is public only so that each leaf is a fresh heap
/// tuple: written as `Node(Empty, Empty)`, or with `Empty` passed between private
/// functions, the Erlang compiler folds the leaf into one shared literal, and the SPEC
/// requires one allocation per node.
pub fn make(d: Int, empty: Tree) -> Tree {
  case d {
    0 -> Node(empty, empty)
    _ -> Node(make(d - 1, empty), make(d - 1, empty))
  }
}

/// The number of nodes, by walking the whole tree.
fn check(tree: Tree) -> Int {
  case tree {
    Empty -> 0
    Node(left, right) -> 1 + check(left) + check(right)
  }
}

/// Builds and checks `iterations` fresh trees of depth `d`, summing the checks.
fn sum_trees(iterations: Int, d: Int, total: Int) -> Int {
  case iterations {
    0 -> total
    _ -> sum_trees(iterations - 1, d, total + check(make(d, Empty)))
  }
}

fn depths(d: Int, n: Int) -> Nil {
  case d <= n {
    False -> Nil
    True -> {
      let iterations = int.bitwise_shift_left(1, n - d + min_depth)
      let total = sum_trees(iterations, d, 0)
      io.println(
        int.to_string(iterations)
        <> "\t trees of depth "
        <> int.to_string(d)
        <> "\t check: "
        <> int.to_string(total),
      )
      depths(d + 2, n)
    }
  }
}

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)

  let stretch_depth = n + 1
  io.println(
    "stretch tree of depth "
    <> int.to_string(stretch_depth)
    <> "\t check: "
    <> int.to_string(check(make(stretch_depth, Empty))),
  )

  let long_lived = make(n, Empty)
  depths(min_depth, n)

  io.println(
    "long lived tree of depth "
    <> int.to_string(n)
    <> "\t check: "
    <> int.to_string(check(long_lived)),
  )
}
