// mandelbrot: escape-time iteration on an N x N grid; prints the inside count, iterations, checksum.

import std/os/env
import std/num/float64

val max-iter = 50

// The number of updates before z escapes, at most max-iter.
fun escape-time(cr : float64, ci : float64, zr : float64, zi : float64, i : int) : div int
  if i >= max-iter then i
  else
    val zr2 = zr * zr
    val zi2 = zi * zi
    if zr2 + zi2 > 4.0 then i
    else escape-time(cr, ci, zr2 - zi2 + cr, 2.0 * zr * zi + ci, i + 1)

struct totals
  inside : int
  iterations : int
  checksum : int

fun columns(n : int, nf : float64, y : int, ci : float64, x : int, t : totals) : div totals
  if x >= n then t
  else
    val cr = 2.0 * x.float64 / nf - 1.5
    val i = escape-time(cr, ci, 0.0, 0.0, 0)
    val t1 = if i == max-iter
      then Totals(t.inside + 1, t.iterations + i, t.checksum + (y * n + x))
      else t(iterations = t.iterations + i)
    columns(n, nf, y, ci, x + 1, t1)

fun rows(n : int, nf : float64, y : int, t : totals) : div totals
  if y >= n then t
  else
    val ci = 2.0 * y.float64 / nf - 1.0
    rows(n, nf, y + 1, columns(n, nf, y, ci, 0, t))

pub fun main()
  val n = get-args().head.default("0").parse-int.default(0)
  val t = rows(n, n.float64, 0, Totals(0, 0, 0))
  println("inside " ++ t.inside.show)
  println("iterations " ++ t.iterations.show)
  println("checksum " ++ (t.checksum % 4294967296).show)
