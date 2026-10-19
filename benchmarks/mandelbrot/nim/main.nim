# mandelbrot: escape-time iteration on an N x N grid over [-1.5, 0.5] x [-1, 1], at most
# 50 iterations per point. Prints the inside count, the total iterations and a checksum.

import std/[os, strutils]

const maxIter = 50

proc escapeTime(cr, ci: float): int =
  var zr = 0.0
  var zi = 0.0
  var i = 0
  while i < maxIter:
    let zr2 = zr * zr
    let zi2 = zi * zi
    if zr2 + zi2 > 4.0: break
    zi = 2.0 * zr * zi + ci
    zr = zr2 - zi2 + cr
    inc i
  i

proc main() =
  let n = parseInt(paramStr(1))
  let fn = float(n)
  var inside = 0
  var iterations = 0
  var checksum = 0
  for y in 0 ..< n:
    let ci = 2.0 * float(y) / fn - 1.0
    for x in 0 ..< n:
      let cr = 2.0 * float(x) / fn - 1.5
      let i = escapeTime(cr, ci)
      iterations += i
      if i == maxIter:
        inc inside
        checksum += y * n + x
  echo "inside ", inside
  echo "iterations ", iterations
  echo "checksum ", checksum mod (1 shl 32)

main()
