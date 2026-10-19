// fannkuch-redux: walks every permutation of 0..n in a fixed order and counts the prefix
// reversals that bring 0 to the front. Prints a checksum and the maximum flip count.

function fannkuch(n: number): [number, number] {
  const perm1 = new Int32Array(n);
  for (let i = 0; i < n; i++) perm1[i] = i;
  const perm = new Int32Array(n);
  const count = new Int32Array(n);
  let maxFlips = 0;
  let checksum = 0;
  let permIndex = 0;
  let r = n;

  for (;;) {
    // 1. Reset the counters below r.
    while (r !== 1) {
      count[r - 1] = r;
      r--;
    }

    // 2. Count the flips of the current permutation, on a copy.
    perm.set(perm1);
    let flips = 0;
    let k = perm[0];
    while (k !== 0) {
      for (let i = 0, j = k; i < j; i++, j--) {
        const t = perm[i];
        perm[i] = perm[j];
        perm[j] = t;
      }
      flips++;
      k = perm[0];
    }
    if (flips > maxFlips) maxFlips = flips;
    checksum += permIndex % 2 === 0 ? flips : -flips;

    // 3. Advance perm1 to the next permutation.
    for (;;) {
      if (r === n) return [checksum, maxFlips];
      const first = perm1[0];
      for (let i = 0; i < r; i++) perm1[i] = perm1[i + 1];
      perm1[r] = first;
      count[r]--;
      if (count[r] > 0) break;
      r++;
    }
    permIndex++;
  }
}

function main(arg: string): void {
  const nArg = Number.parseInt(arg, 10);
  const [checksum, maxFlips] = fannkuch(Math.max(nArg, 1));
  console.log(String(checksum));
  console.log(`Pfannkuchen(${nArg}) = ${maxFlips}`);
}

main(process.argv[2] ?? "0");
