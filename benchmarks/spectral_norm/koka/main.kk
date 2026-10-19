// spectral_norm: estimates the spectral norm of an infinite matrix with the power method, on lists.

import std/os/env
import std/num/float64

// One entry of row i of A times x: sum over j of A(i, j) * x[j], j in increasing order.
fun sum-row(i : int, x : list<float64>, j : int, s : float64) : float64
  match x
    Nil -> s
    Cons(xj, xs) ->
      val ij = i + j
      sum-row(i, xs, j + 1, s + 1.0 / (ij * (ij + 1) / 2 + i + 1).float64 * xj)

// One entry of the transposed product: sum over j of A(j, i) * x[j].
fun sum-col(i : int, x : list<float64>, j : int, s : float64) : float64
  match x
    Nil -> s
    Cons(xj, xs) ->
      val ij = i + j
      sum-col(i, xs, j + 1, s + 1.0 / (ij * (ij + 1) / 2 + j + 1).float64 * xj)

fun times-a(indices : list<int>, x : list<float64>) : list<float64>
  indices.map(fn(i) sum-row(i, x, 0, 0.0))

fun times-at(indices : list<int>, x : list<float64>) : list<float64>
  indices.map(fn(i) sum-col(i, x, 0, 0.0))

fun times-ata(indices : list<int>, x : list<float64>) : list<float64>
  times-at(indices, times-a(indices, x))

// The power method: `rounds` rounds of v = AtA u, u = AtA v. Returns (u, v).
fun power(indices : list<int>, u : list<float64>, v : list<float64>, rounds : int) : div (list<float64>, list<float64>)
  if rounds == 0 then (u, v)
  else
    val v1 = times-ata(indices, u)
    val u1 = times-ata(indices, v1)
    power(indices, u1, v1, rounds - 1)

// (vBv, vv) over u and v together, in increasing i.
fun dots(u : list<float64>, v : list<float64>, vbv : float64, vv : float64) : div (float64, float64)
  match (u, v)
    (Cons(ui, us), Cons(vi, vs)) -> dots(us, vs, vbv + ui * vi, vv + vi * vi)
    _ -> (vbv, vv)

// round(x) with halves away from zero.
fun round-away(x : float64) : int
  val t = x.truncate
  val r = if abs(x - t) >= 0.5 then t + (if x < 0.0 then -1.0 else 1.0) else t
  r.int

pub fun main()
  val n = get-args().head.default("0").parse-int.default(0)
  val indices = list(0, n - 1)
  val ones = indices.map(fn(_) 1.0)
  val (u, v) = power(indices, ones, ones, 10)
  val (vbv, vv) = dots(u, v, 0.0, 0.0)
  val result = if vv == 0.0 then 0 else round-away(sqrt(vbv / vv) * 1.0e9)
  println(result.show)
