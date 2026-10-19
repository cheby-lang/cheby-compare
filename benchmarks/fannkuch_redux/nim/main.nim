# fannkuch_redux: counts pancake flips over every permutation of 0..n-1, in the order the
# counting algorithm generates them. Prints the alternating checksum and the maximum flip count.

import std/[os, strutils, algorithm]

proc fannkuch(n: int): tuple[checksum, maxFlips: int] =
  var perm1 = newSeq[int](n)
  for i in 0 ..< n: perm1[i] = i
  var perm = newSeq[int](n)
  var count = newSeq[int](n)
  var maxFlips = 0
  var checksum = 0
  var permIndex = 0
  var r = n
  while true:
    while r != 1:
      count[r - 1] = r
      dec r

    for i in 0 ..< n: perm[i] = perm1[i]
    var flips = 0
    var k = perm[0]
    while k != 0:
      perm.reverse(0, k)
      inc flips
      k = perm[0]
    maxFlips = max(maxFlips, flips)
    if permIndex mod 2 == 0: checksum += flips
    else: checksum -= flips

    while true:
      if r == n: return (checksum, maxFlips)
      let first = perm1[0]
      for i in 0 ..< r: perm1[i] = perm1[i + 1]
      perm1[r] = first
      dec count[r]
      if count[r] > 0: break
      inc r
    inc permIndex

let bigN = parseInt(paramStr(1))
let (checksum, maxFlips) = fannkuch(max(bigN, 1))
echo checksum
echo "Pfannkuchen(", bigN, ") = ", maxFlips
