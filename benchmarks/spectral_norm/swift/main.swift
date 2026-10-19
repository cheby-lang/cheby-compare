// Spectral norm: the benchmarks-game power method on the matrix
// A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.

/// The entry A(i, j) of the matrix.
func entry(_ i: Int, _ j: Int) -> Double {
  1.0 / Double((i + j) * (i + j + 1) / 2 + i + 1)
}

/// Writes A times `x` into `out`.
func timesA(_ x: [Double], _ out: inout [Double]) {
  for i in out.indices {
    var sum = 0.0
    for j in x.indices {
      sum += entry(i, j) * x[j]
    }
    out[i] = sum
  }
}

/// Writes A transposed times `x` into `out`.
func timesAt(_ x: [Double], _ out: inout [Double]) {
  for i in out.indices {
    var sum = 0.0
    for j in x.indices {
      sum += entry(j, i) * x[j]
    }
    out[i] = sum
  }
}

/// Writes A transposed times A times `x` into `out`, using `tmp`.
func timesAtA(_ x: [Double], _ tmp: inout [Double], _ out: inout [Double]) {
  timesA(x, &tmp)
  timesAt(tmp, &out)
}

func dot(_ x: [Double], _ y: [Double]) -> Double {
  var sum = 0.0
  for i in x.indices {
    sum += x[i] * y[i]
  }
  return sum
}

let n = Int(CommandLine.arguments[1])!
var u = [Double](repeating: 1.0, count: n)
var v = [Double](repeating: 0.0, count: n)
var tmp = [Double](repeating: 0.0, count: n)
for _ in 0..<10 {
  timesAtA(u, &tmp, &v)
  timesAtA(v, &tmp, &u)
}
let vv = dot(v, v)
let result = vv == 0.0 ? 0 : Int(((dot(u, v) / vv).squareRoot() * 1e9).rounded())
print(result)
