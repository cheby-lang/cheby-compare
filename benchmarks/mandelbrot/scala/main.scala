// Mandelbrot: escape-time iteration on an N x N grid over [-1.5, 0.5] x [-1, 1].
// Prints the inside count, the total iterations and a checksum of the inside points.

val MaxIter = 50

/** The number of updates before z escapes, at most MaxIter. */
def escapeTime(cr: Double, ci: Double): Int =
  var zr = 0.0
  var zi = 0.0
  var i = 0
  var escaped = false
  while !escaped && i < MaxIter do
    val zr2 = zr * zr
    val zi2 = zi * zi
    if zr2 + zi2 > 4.0 then escaped = true
    else
      zi = 2.0 * zr * zi + ci
      zr = zr2 - zi2 + cr
      i += 1
  i

@main def main(n: Int): Unit =
  val fn = n.toDouble
  var inside = 0L
  var iterations = 0L
  var checksum = 0L
  var y = 0
  while y < n do
    val ci = 2.0 * y.toDouble / fn - 1.0
    var x = 0
    while x < n do
      val cr = 2.0 * x.toDouble / fn - 1.5
      val i = escapeTime(cr, ci)
      iterations += i
      if i == MaxIter then
        inside += 1
        checksum += y.toLong * n + x
      x += 1
    y += 1
  println(s"inside $inside")
  println(s"iterations $iterations")
  println(s"checksum ${checksum & 0xFFFFFFFFL}")
