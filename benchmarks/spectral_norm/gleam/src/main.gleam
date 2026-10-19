//// Spectral norm: 10 rounds of the power method on A^T A, with vectors as lists of floats.

import gleam/float
import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

// The correctly rounded square root. gleam/float's square_root is math:pow(x, 0.5).
@external(erlang, "math", "sqrt")
fn sqrt(x: Float) -> Float

/// The matrix entry A(i, j), with an integer denominator.
fn a(i: Int, j: Int) -> Float {
  1.0 /. int.to_float({ i + j } * { i + j + 1 } / 2 + i + 1)
}

/// The sum over j of A(i, j) * x[j], from j = 0 up.
fn row_sum(i: Int, x: List(Float), j: Int, s: Float) -> Float {
  case x {
    [] -> s
    [xj, ..rest] -> row_sum(i, rest, j + 1, s +. a(i, j) *. xj)
  }
}

/// The sum over j of A(j, i) * x[j], from j = 0 up.
fn col_sum(i: Int, x: List(Float), j: Int, s: Float) -> Float {
  case x {
    [] -> s
    [xj, ..rest] -> col_sum(i, rest, j + 1, s +. a(j, i) *. xj)
  }
}

fn times_a(x: List(Float), indices: List(Int)) -> List(Float) {
  list.map(indices, fn(i) { row_sum(i, x, 0, 0.0) })
}

fn times_at(x: List(Float), indices: List(Int)) -> List(Float) {
  list.map(indices, fn(i) { col_sum(i, x, 0, 0.0) })
}

fn times_ata(x: List(Float), indices: List(Int)) -> List(Float) {
  times_at(times_a(x, indices), indices)
}

fn rounds(
  k: Int,
  u: List(Float),
  v: List(Float),
  indices: List(Int),
) -> #(List(Float), List(Float)) {
  case k {
    0 -> #(u, v)
    _ -> {
      let v = times_ata(u, indices)
      let u = times_ata(v, indices)
      rounds(k - 1, u, v, indices)
    }
  }
}

fn dots(
  u: List(Float),
  v: List(Float),
  vbv: Float,
  vv: Float,
) -> #(Float, Float) {
  case u, v {
    [ui, ..us], [vi, ..vs] -> dots(us, vs, vbv +. ui *. vi, vv +. vi *. vi)
    _, _ -> #(vbv, vv)
  }
}

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)

  let indices = int.range(from: n - 1, to: -1, with: [], run: list.prepend)
  let u = list.repeat(1.0, n)
  let #(u, v) = rounds(10, u, u, indices)
  let #(vbv, vv) = dots(u, v, 0.0, 0.0)
  let result = case vv == 0.0 {
    True -> 0
    False -> float.round(sqrt(vbv /. vv) *. 1.0e9)
  }
  io.println(int.to_string(result))
}
