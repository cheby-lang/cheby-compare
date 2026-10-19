// Spectral norm: 10 rounds of the power method on an n-by-n matrix, single-threaded.
// Prints round(sqrt(vBv / vv) * 10^9).

/** Entry (i, j) of the infinite matrix A, recomputed on every use. */
inline def a(i: Int, j: Int): Double =
  1.0 / ((i + j) * (i + j + 1) / 2 + i + 1).toDouble

/** out = A x */
def timesA(x: Array[Double], out: Array[Double]): Unit =
  val n = x.length
  var i = 0
  while i < n do
    var s = 0.0
    var j = 0
    while j < n do
      s = s + a(i, j) * x(j)
      j += 1
    out(i) = s
    i += 1

/** out = A^T x */
def timesAt(x: Array[Double], out: Array[Double]): Unit =
  val n = x.length
  var i = 0
  while i < n do
    var s = 0.0
    var j = 0
    while j < n do
      s = s + a(j, i) * x(j)
      j += 1
    out(i) = s
    i += 1

/** out = A^T A x, through the scratch vector `tmp`. */
def timesAtA(x: Array[Double], out: Array[Double], tmp: Array[Double]): Unit =
  timesA(x, tmp)
  timesAt(tmp, out)

@main def main(n: Int): Unit =
  val u = Array.fill(n)(1.0)
  val v = new Array[Double](n)
  val tmp = new Array[Double](n)
  for _ <- 1 to 10 do
    timesAtA(u, v, tmp)
    timesAtA(v, u, tmp)
  var vBv = 0.0
  var vv = 0.0
  var i = 0
  while i < n do
    vBv = vBv + u(i) * v(i)
    vv = vv + v(i) * v(i)
    i += 1
  val result =
    if vv == 0.0 then 0L
    else
      val x = math.sqrt(vBv / vv) * 1.0e9
      if x < 0 then -math.round(-x) else math.round(x)
  println(result)
