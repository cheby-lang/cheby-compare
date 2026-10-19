#!/usr/bin/env python3
"""Inputs for the json_roundtrip benchmark: json-0.json, json-test.json, json-bench.json.

Each file is one JSON array of records, one record per line, with a space after each `:` and `,`.
Every number is an integer, and every string holds only the letters a-z, the digits 0-9 and
spaces, so no string needs an escape. Everything comes from one 64-bit LCG with wrapping
arithmetic, so the files are byte-identical on every machine. See
benchmarks/json_roundtrip/SPEC.md, "Data".

Usage: gen_json.py DATA_DIR
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

MASK = (1 << 64) - 1
MUL = 6364136223846793005
INC = 1442695040888963407
SEED = 7

LETTERS = "abcdefghijklmnopqrstuvwxyz"
TAGS = [
    "alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta",
    "iota", "kappa", "lambda", "mu", "nu", "xi", "omicron", "pi",
]
RECORDS = {  # file name -> number of records
    "json-0.json": 0,
    "json-test.json": 1_000,
    "json-bench.json": 50_000,
}


def generate_records(n_records: int) -> list[dict]:
    state = SEED

    def next31() -> int:
        nonlocal state
        state = (state * MUL + INC) & MASK
        return state >> 33

    def word() -> str:
        length = 3 + next31() % 8
        return "".join(LETTERS[next31() % 26] for _ in range(length))

    records = []
    for i in range(n_records):
        # The statements run in this order; each next31() call is one step of the LCG.
        rid = i + 1
        first = word()
        last = word()
        active = next31() % 4 != 0
        score = next31() % 2001 - 1000
        n_tags = next31() % 5
        tags = [TAGS[next31() % 16] for _ in range(n_tags)]
        number = 1 + next31() % 9999
        street = f"{number} {word()} street"
        city = word()
        zip_code = 10000 + next31() % 90000
        n_history = next31() % 9
        history = []
        for _ in range(n_history):
            day = 1 + next31() % 365
            amount = next31() % 10000
            history.append({"day": day, "amount": amount})
        records.append({
            "id": rid,
            "name": f"{first} {last}",
            "active": active,
            "score": score,
            "tags": tags,
            "address": {"street": street, "city": city, "zip": zip_code},
            "history": history,
        })
    return records


def generate_text(n_records: int) -> bytes:
    records = generate_records(n_records)
    if not records:
        return b"[]\n"
    lines = [json.dumps(r, separators=(", ", ": ")) for r in records]
    return ("[\n" + ",\n".join(lines) + "\n]\n").encode("ascii")


def generate(data_dir: Path) -> None:
    data_dir = Path(data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)
    for name, n in RECORDS.items():
        (data_dir / name).write_bytes(generate_text(n))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    generate(Path(sys.argv[1]))
