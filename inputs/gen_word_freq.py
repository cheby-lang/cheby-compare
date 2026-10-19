#!/usr/bin/env python3
"""Inputs for the word_freq benchmark: words-0.txt, words-test.txt, words-bench.txt.

Each file is lowercase ASCII text: words of the letters a-z, separated by single spaces within a
line, lines ended by "\\n", and now and then an empty line. The words come from a generated
vocabulary with a Zipf-like skew. Everything comes from one 64-bit LCG with wrapping arithmetic,
so the files are byte-identical on every machine. See benchmarks/word_freq/SPEC.md, "Data".

Usage: gen_word_freq.py DATA_DIR
"""

from __future__ import annotations

import sys
from pathlib import Path

MASK = (1 << 64) - 1
MUL = 6364136223846793005
INC = 1442695040888963407
SEED = 42

BUCKETS = 18  # vocabulary size 2^18 - 1 = 262143
WORDS = {  # file name -> number of words
    "words-0.txt": 0,
    "words-test.txt": 20_000,
    "words-bench.txt": 12_000_000,
}


def generate_text(n_words: int) -> bytes:
    state = SEED

    def next31() -> int:
        nonlocal state
        state = (state * MUL + INC) & MASK
        return state >> 33

    vocab_size = (1 << BUCKETS) - 1
    letters = "abcdefghijklmnopqrstuvwxyz"
    vocab = []
    for _ in range(vocab_size):
        length = 2 + next31() % 9
        vocab.append("".join(letters[next31() % 26] for _ in range(length)))

    out: list[str] = []
    remaining = n_words
    while remaining > 0:
        k = min(1 + next31() % 16, remaining)
        line = []
        for _ in range(k):
            b = next31() % BUCKETS
            line.append(vocab[(1 << b) - 1 + next31() % (1 << b)])
        out.append(" ".join(line))
        out.append("\n")
        if next31() % 8 == 0:
            out.append("\n")
        remaining -= k
    return "".join(out).encode("ascii")


def generate(data_dir: Path) -> None:
    data_dir = Path(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    for name, n in WORDS.items():
        (data_dir / name).write_bytes(generate_text(n))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    generate(Path(sys.argv[1]))
