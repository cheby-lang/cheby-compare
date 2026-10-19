// Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.

let maxIter = 50

/// The number of iterations before the point (cr, ci) escapes, or `maxIter`.
func escapeTime(_ cr: Double, _ ci: Double) -> Int {
  var zr = 0.0
  var zi = 0.0
  var i = 0
  while i < maxIter {
    let zr2 = zr * zr
    let zi2 = zi * zi
    if zr2 + zi2 > 4.0 {
      break
    }
    zi = 2.0 * zr * zi + ci
    zr = zr2 - zi2 + cr
    i += 1
  }
  return i
}

let n = Int(CommandLine.arguments[1])!
let nf = Double(n)
var inside = 0
var iterations = 0
var checksum = 0
for y in 0..<n {
  let ci = 2.0 * Double(y) / nf - 1.0
  for x in 0..<n {
    let cr = 2.0 * Double(x) / nf - 1.5
    let i = escapeTime(cr, ci)
    iterations += i
    if i == maxIter {
      inside += 1
      checksum += y * n + x
    }
  }
}
print("inside \(inside)")
print("iterations \(iterations)")
print("checksum \(checksum % (1 << 32))")
