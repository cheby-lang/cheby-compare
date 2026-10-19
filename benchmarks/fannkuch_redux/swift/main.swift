// Fannkuch-redux: flips over every permutation of 0..n, in the order the counting algorithm
// generates them. Prints the alternating checksum and the maximum flip count.

/// Returns (checksum, maxFlips) over all permutations of 0..n, n >= 1.
func fannkuch(_ n: Int) -> (checksum: Int, maxFlips: Int) {
  var perm1 = Array(0..<n)
  var perm = [Int](repeating: 0, count: n)
  var count = [Int](repeating: 0, count: n)
  var maxFlips = 0
  var checksum = 0
  var permIndex = 0
  var r = n
  while true {
    while r != 1 {
      count[r - 1] = r
      r -= 1
    }

    for i in 0..<n {
      perm[i] = perm1[i]
    }
    var flips = 0
    var k = perm[0]
    while k != 0 {
      var lo = 0
      var hi = k
      while lo < hi {
        perm.swapAt(lo, hi)
        lo += 1
        hi -= 1
      }
      flips += 1
      k = perm[0]
    }
    maxFlips = max(maxFlips, flips)
    checksum += permIndex % 2 == 0 ? flips : -flips

    while true {
      if r == n {
        return (checksum, maxFlips)
      }
      let first = perm1[0]
      for i in 0..<r {
        perm1[i] = perm1[i + 1]
      }
      perm1[r] = first
      count[r] -= 1
      if count[r] > 0 {
        break
      }
      r += 1
    }
    permIndex += 1
  }
}

let n = Int(CommandLine.arguments[1])!
let (checksum, maxFlips) = fannkuch(max(n, 1))
print(checksum)
print("Pfannkuchen(\(n)) = \(maxFlips)")
