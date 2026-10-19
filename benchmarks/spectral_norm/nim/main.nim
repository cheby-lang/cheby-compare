# spectral_norm: estimates the largest singular value of the n x n matrix A(i, j) with 10
# rounds of the power method. Prints round(sqrt(vBv / vv) * 10^9).

import std/[os, strutils, math]

proc a(i, j: int): float {.inline.} =
  1.0 / float((i + j) * (i + j + 1) div 2 + i + 1)

proc timesA(x: seq[float], res: var seq[float]) =
  let n = x.len
  for i in 0 ..< n:
    var s = 0.0
    for j in 0 ..< n:
      s += a(i, j) * x[j]
    res[i] = s

proc timesAt(x: seq[float], res: var seq[float]) =
  let n = x.len
  for i in 0 ..< n:
    var s = 0.0
    for j in 0 ..< n:
      s += a(j, i) * x[j]
    res[i] = s

proc timesAtA(x: seq[float], tmp, res: var seq[float]) =
  timesA(x, tmp)
  timesAt(tmp, res)

proc main() =
  let n = parseInt(paramStr(1))
  var u = newSeq[float](n)
  for i in 0 ..< n: u[i] = 1.0
  var v = newSeq[float](n)
  var tmp = newSeq[float](n)
  for _ in 1 .. 10:
    timesAtA(u, tmp, v)
    timesAtA(v, tmp, u)
  var vBv = 0.0
  var vv = 0.0
  for i in 0 ..< n:
    vBv += u[i] * v[i]
    vv += v[i] * v[i]
  if vv == 0.0:
    echo 0
  else:
    echo int64(round(sqrt(vBv / vv) * 1e9))

main()
