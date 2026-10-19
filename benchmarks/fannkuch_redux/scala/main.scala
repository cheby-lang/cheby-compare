// Fannkuch-redux: counts prefix flips over every permutation of 0..n, single-threaded.
// Prints the alternating checksum and the maximum flip count.

/** Returns (checksum, maxFlips) over all permutations of 0..n-1, n >= 1. */
def fannkuch(n: Int): (Int, Int) =
  val perm1 = Array.tabulate(n)(identity)
  val perm = new Array[Int](n)
  val count = new Array[Int](n)
  var maxFlips = 0
  var checksum = 0
  var permIndex = 0
  var r = n
  while true do
    while r != 1 do
      count(r - 1) = r
      r -= 1

    System.arraycopy(perm1, 0, perm, 0, n)
    var flips = 0
    var k = perm(0)
    while k != 0 do
      var lo = 0
      var hi = k
      while lo < hi do
        val t = perm(lo)
        perm(lo) = perm(hi)
        perm(hi) = t
        lo += 1
        hi -= 1
      flips += 1
      k = perm(0)
    maxFlips = math.max(maxFlips, flips)
    checksum += (if permIndex % 2 == 0 then flips else -flips)

    var advanced = false
    while !advanced do
      if r == n then return (checksum, maxFlips)
      val first = perm1(0)
      var i = 0
      while i < r do
        perm1(i) = perm1(i + 1)
        i += 1
      perm1(r) = first
      count(r) -= 1
      if count(r) > 0 then advanced = true
      else r += 1
    permIndex += 1
  throw IllegalStateException("unreachable")

@main def main(n: Int): Unit =
  val (checksum, maxFlips) = fannkuch(math.max(n, 1))
  println(checksum)
  println(s"Pfannkuchen($n) = $maxFlips")
