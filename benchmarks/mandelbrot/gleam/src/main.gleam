//// Mandelbrot: escape-time iteration on an N x N grid, counting the inside points.

import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

const max_iter = 50

type Totals {
  Totals(inside: Int, iterations: Int, checksum: Int)
}

/// The number of updates before `z` escapes, at most `max_iter`.
fn escape_time(cr: Float, ci: Float, zr: Float, zi: Float, i: Int) -> Int {
  case i < max_iter {
    False -> i
    True -> {
      let zr2 = zr *. zr
      let zi2 = zi *. zi
      case zr2 +. zi2 >. 4.0 {
        True -> i
        False ->
          // zi is updated with the old zr.
          escape_time(cr, ci, zr2 -. zi2 +. cr, 2.0 *. zr *. zi +. ci, i + 1)
      }
    }
  }
}

fn columns(
  x: Int,
  y: Int,
  n: Int,
  fnum: Float,
  ci: Float,
  totals: Totals,
) -> Totals {
  case x < n {
    False -> totals
    True -> {
      let cr = 2.0 *. int.to_float(x) /. fnum -. 1.5
      let i = escape_time(cr, ci, 0.0, 0.0, 0)
      let Totals(inside, iterations, checksum) = totals
      let totals = case i == max_iter {
        True -> Totals(inside + 1, iterations + i, checksum + y * n + x)
        False -> Totals(inside, iterations + i, checksum)
      }
      columns(x + 1, y, n, fnum, ci, totals)
    }
  }
}

fn rows(y: Int, n: Int, fnum: Float, totals: Totals) -> Totals {
  case y < n {
    False -> totals
    True -> {
      let ci = 2.0 *. int.to_float(y) /. fnum -. 1.0
      rows(y + 1, n, fnum, columns(0, y, n, fnum, ci, totals))
    }
  }
}

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(n) = int.parse(arg)

  let Totals(inside, iterations, checksum) =
    rows(0, n, int.to_float(n), Totals(0, 0, 0))

  io.println("inside " <> int.to_string(inside))
  io.println("iterations " <> int.to_string(iterations))
  io.println(
    "checksum " <> int.to_string(int.bitwise_and(checksum, 0xFFFFFFFF)),
  )
}
