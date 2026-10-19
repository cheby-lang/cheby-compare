// spectral-norm: estimates the largest singular value of an n by n matrix with 10 rounds
// of the power method, and prints it as round(x * 10^9).

// The denominator in 32-bit integer arithmetic: the product stays below 4n^2 (about 1.2e8 at
// n = 5500), and the product is even, so the shift is the exact halving.
function a(i: number, j: number): number {
  return 1.0 / ((((i + j) * (i + j + 1)) >>> 1) + i + 1);
}

// out = A * x
function timesA(x: Float64Array, out: Float64Array): void {
  const n = x.length;
  for (let i = 0; i < n; i++) {
    let s = 0.0;
    for (let j = 0; j < n; j++) {
      s += a(i, j) * x[j];
    }
    out[i] = s;
  }
}

// out = A^T * x
function timesAt(x: Float64Array, out: Float64Array): void {
  const n = x.length;
  for (let i = 0; i < n; i++) {
    let s = 0.0;
    for (let j = 0; j < n; j++) {
      s += a(j, i) * x[j];
    }
    out[i] = s;
  }
}

// out = A^T * A * x, through the scratch vector tmp
function timesAtA(x: Float64Array, out: Float64Array, tmp: Float64Array): void {
  timesA(x, tmp);
  timesAt(tmp, out);
}

function main(n: number): void {
  const u = new Float64Array(n).fill(1.0);
  const v = new Float64Array(n);
  const tmp = new Float64Array(n);
  for (let round = 0; round < 10; round++) {
    timesAtA(u, v, tmp);
    timesAtA(v, u, tmp);
  }
  let vBv = 0.0;
  let vv = 0.0;
  for (let i = 0; i < n; i++) {
    vBv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  // The value is positive, so Math.round is half away from zero here.
  const result = vv === 0.0 ? 0 : Math.round(Math.sqrt(vBv / vv) * 1e9);
  console.log(String(result));
}

main(Number.parseInt(process.argv[2] ?? "0", 10));
