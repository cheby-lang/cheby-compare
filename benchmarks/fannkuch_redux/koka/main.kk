// fannkuch_redux: walks every permutation of 0..n-1, counting the prefix reversals of each.

import std/os/env

// v with v[i] set to x. A vector is a value: the write copies v when it is shared and updates it
// in place when it is unique (Koka's reuse of unique values).
fun set(v : vector<int>, i : int, x : int) : exn vector<int>
  var w := v
  w[i] := x
  w

// Reverses perm[i..j], both ends included. The first write copies perm when the caller still
// holds it (perm1), and the later writes update the copy in place.
fun flip(perm : vector<int>, i : int, j : int) : <div,exn> vector<int>
  if i >= j then perm
  else
    val t = perm[i]
    flip(perm.set(i, perm[j]).set(j, t), i + 1, j - 1)

// The number of flips that bring 0 to the front, counted by doing them.
fun count-flips(perm : vector<int>, flips : int) : <div,exn> int
  val k = perm[0]
  if k == 0 then flips else count-flips(flip(perm, 0, k), flips + 1)

// Resets the counters below r: count[r - 1] = r while r != 1. Returns the counters and r = 1.
fun reset(count : vector<int>, r : int) : <div,exn> (vector<int>, int)
  if r == 1 then (count, r) else reset(count.set(r - 1, r), r - 1)

// Shifts perm[i..r - 1] left by one: perm[i] = perm[i + 1], up to i = r - 1.
fun shift(perm : vector<int>, i : int, r : int) : <div,exn> vector<int>
  if i >= r then perm else shift(perm.set(i, perm[i + 1]), i + 1, r)

// Advances perm1 to the next permutation: the new (perm1, count, r), or Nothing after the last.
fun next-perm(perm1 : vector<int>, count : vector<int>, r : int, n : int) : <div,exn> maybe<(vector<int>, vector<int>, int)>
  if r == n then Nothing
  else
    // Rotate perm1[0..r] left by one: the first element moves to index r.
    val first = perm1[0]
    val perm2 = shift(perm1, 0, r).set(r, first)
    val c = count[r] - 1
    val count2 = count.set(r, c)
    if c > 0 then Just((perm2, count2, r)) else next-perm(perm2, count2, r + 1, n)

// (checksum, max_flips) over the permutations from perm1 on.
fun walk(perm1 : vector<int>, count : vector<int>, r : int, n : int, perm-index : int,
         checksum : int, max-flips : int) : <div,exn> (int, int)
  // 1. Reset the counters below r.
  val (count1, r1) = reset(count, r)
  // 2. Count the flips of the current permutation.
  val flips = count-flips(perm1, 0)
  val max-flips1 = max(max-flips, flips)
  val checksum1 = if perm-index.is-even then checksum + flips else checksum - flips
  // 3. Advance perm1 to the next permutation.
  match next-perm(perm1, count1, r1, n)
    Nothing -> (checksum1, max-flips1)
    Just((perm2, count2, r2)) -> walk(perm2, count2, r2, n, perm-index + 1, checksum1, max-flips1)

// (checksum, max_flips) over all n! permutations, n >= 1.
fun fannkuch(n : int) : <div,exn> (int, int)
  walk(vector-init(n, fn(i) i), vector(n, 0), n, n, 0, 0, 0)

pub fun main()
  val big-n = get-args().head.default("0").parse-int.default(0)
  val (checksum, max-flips) = fannkuch(max(big-n, 1))
  println(checksum.show)
  println("Pfannkuchen(" ++ big-n.show ++ ") = " ++ max-flips.show)
