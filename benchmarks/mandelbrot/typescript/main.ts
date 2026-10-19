// mandelbrot: escape-time iteration on an N x N grid over [-1.5, 0.5] x [-1, 1], at most
// 50 iterations per point. Prints the inside count, total iterations and a position checksum.

const MAX_ITER = 50;

function escapeTime(cr: number, ci: number): number {
  let zr = 0.0;
  let zi = 0.0;
  let i = 0;
  while (i < MAX_ITER) {
    const zr2 = zr * zr;
    const zi2 = zi * zi;
    if (zr2 + zi2 > 4.0) break;
    zi = 2.0 * zr * zi + ci;
    zr = zr2 - zi2 + cr;
    i++;
  }
  return i;
}

function main(n: number): void {
  const fn = n;
  // Plain numbers: checksum stays below 2^53 for N <= 9000.
  let inside = 0;
  let iterations = 0;
  let checksum = 0;
  for (let y = 0; y < n; y++) {
    const ci = (2.0 * y) / fn - 1.0;
    for (let x = 0; x < n; x++) {
      const cr = (2.0 * x) / fn - 1.5;
      const i = escapeTime(cr, ci);
      iterations += i;
      if (i === MAX_ITER) {
        inside++;
        checksum += y * n + x;
      }
    }
  }
  console.log(`inside ${inside}`);
  console.log(`iterations ${iterations}`);
  console.log(`checksum ${checksum % 2 ** 32}`);
}

main(Number.parseInt(process.argv[2] ?? "0", 10));
