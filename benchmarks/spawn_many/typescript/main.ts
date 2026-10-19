// spawn_many: spawns n short async tasks in batches of 1000, joins each batch and prints the sum.

const B = 1000;
const ROUNDS = 10;
const MODULUS = 2147483647; // 2^31 - 1
const MULTIPLIER = 48271; // the MINSTD generator

/** Ten MINSTD steps from index + 1; every product stays below 2^47, exact in a double. */
function work(index: number): number {
  let x = index + 1;
  for (let r = 0; r < ROUNDS; r++) {
    x = (x * MULTIPLIER) % MODULUS;
  }
  return x;
}

/** One task: the first await makes the work run after the spawn, not inside it. */
async function task(index: number): Promise<number> {
  await Promise.resolve();
  return work(index);
}

/** Spawns one task per index of the batch, then joins them all and adds up their results. */
async function spawnAndJoin(start: number, count: number): Promise<number> {
  const batch: Promise<number>[] = [];
  for (let i = start; i < start + count; i++) {
    batch.push(task(i));
  }
  const results = await Promise.all(batch);
  return results.reduce((acc, v) => acc + v, 0);
}

async function main(): Promise<void> {
  const n = Number.parseInt(process.argv[2] ?? "0", 10);
  let sum = 0;
  for (let start = 0; start < n; start += B) {
    sum += await spawnAndJoin(start, Math.min(B, n - start));
  }
  console.log(`tasks: ${n}`);
  console.log(`sum: ${sum}`);
}

await main();
