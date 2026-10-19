// Word frequency: reads a text file, counts its words in a Map and prints the most frequent ones.

import { readFileSync } from "node:fs";

function main(path: string): void {
  const text = readFileSync(path, "latin1");
  const counts = new Map<string, number>();
  let total = 0;
  for (const word of text.split(/\s+/)) {
    if (word === "") continue; // the leading and trailing empty parts
    counts.set(word, (counts.get(word) ?? 0) + 1);
    total++;
  }

  const entries = [...counts];
  entries.sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));

  const lines = [`total ${total}`, `distinct ${counts.size}`];
  for (const [word, count] of entries.slice(0, 20)) {
    lines.push(`${count} ${word}`);
  }
  process.stdout.write(lines.join("\n") + "\n");
}

main(process.argv[2]);
