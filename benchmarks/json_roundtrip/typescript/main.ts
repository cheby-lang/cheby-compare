// JSON round trip: parses an array of records, aggregates and transforms them, and serializes
// the kept records again, with JSON.parse and JSON.stringify.

import { readFileSync } from "node:fs";

const FNV_OFFSET = 2166136261;
const FNV_PRIME = 16777619;

interface Address {
  street: string;
  city: string;
  zip: number;
}

interface Entry {
  day: number;
  amount: number;
}

interface InputRecord {
  id: number;
  name: string;
  active: boolean;
  score: number;
  tags: string[];
  address: Address;
  history: Entry[];
}

interface OutputRecord {
  id: number;
  name: string;
  score: number;
  tags: string[];
  address: Address;
  history: Entry[];
  total: number;
}

function fnv1a(h: number, bytes: Uint8Array): number {
  for (const b of bytes) {
    h = Math.imul(h ^ b, FNV_PRIME) >>> 0;
  }
  return h;
}

function main(path: string, reps: number): void {
  const text = readFileSync(path, "utf8");

  // Every counter stays far below 2^53, so plain numbers are exact.
  let recordsN = 0;
  let activeN = 0;
  let scoreSum = 0;
  let tagsN = 0;
  let historyN = 0;
  let amountSum = 0;
  let outputBytes = 0;
  let h = FNV_OFFSET;

  for (let rep = 0; rep < reps; rep++) {
    const records = JSON.parse(text) as InputRecord[];
    const kept: OutputRecord[] = [];
    for (const r of records) {
      let total = 0;
      for (const e of r.history) total += e.amount;
      recordsN++;
      scoreSum += r.score;
      tagsN += r.tags.length;
      historyN += r.history.length;
      amountSum += total;
      if (r.active) {
        activeN++;
        // Address and history objects keep their parsed key order, so they are shared.
        kept.push({
          id: r.id,
          name: r.name,
          score: r.score + 100 * r.tags.length,
          tags: r.tags,
          address: r.address,
          history: r.history,
          total,
        });
      }
    }
    const out = JSON.stringify(kept);
    outputBytes += Buffer.byteLength(out, "utf8");
    if (rep === reps - 1) {
      h = fnv1a(FNV_OFFSET, Buffer.from(out, "utf8"));
    }
  }

  process.stdout.write(
    `records ${recordsN}\n` +
      `active ${activeN}\n` +
      `score_sum ${scoreSum}\n` +
      `tags ${tagsN}\n` +
      `history ${historyN}\n` +
      `amount_sum ${amountSum}\n` +
      `output_bytes ${outputBytes}\n` +
      `output_fnv1a ${h}\n`,
  );
}

main(process.argv[2], Number.parseInt(process.argv[3], 10));
