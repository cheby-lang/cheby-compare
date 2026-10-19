"""json_roundtrip: parses a JSON array of records, transforms it and serializes it again."""

import json
import sys

FNV_OFFSET = 2166136261
FNV_PRIME = 16777619
MASK32 = 0xFFFFFFFF


def fnv1a(h: int, data: bytes) -> int:
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & MASK32
    return h


def transform(record: dict, total: int) -> dict:
    return {
        "id": record["id"],
        "name": record["name"],
        "score": record["score"] + 100 * len(record["tags"]),
        "tags": record["tags"],
        "address": record["address"],
        "history": record["history"],
        "total": total,
    }


def main() -> None:
    path = sys.argv[1]
    reps = int(sys.argv[2])
    with open(path, "rb") as f:
        text = f.read().decode("ascii")

    records_n = active_n = score_sum = tags_n = history_n = amount_sum = 0
    output_bytes = 0
    h = FNV_OFFSET
    for rep in range(reps):
        records = json.loads(text)
        kept = []
        for record in records:
            total = sum(entry["amount"] for entry in record["history"])
            records_n += 1
            score_sum += record["score"]
            tags_n += len(record["tags"])
            history_n += len(record["history"])
            amount_sum += total
            if record["active"]:
                active_n += 1
                kept.append(transform(record, total))
        out = json.dumps(kept, separators=(",", ":")).encode("ascii")
        output_bytes += len(out)
        if rep == reps - 1:
            h = fnv1a(FNV_OFFSET, out)

    sys.stdout.write(
        f"records {records_n}\n"
        f"active {active_n}\n"
        f"score_sum {score_sum}\n"
        f"tags {tags_n}\n"
        f"history {history_n}\n"
        f"amount_sum {amount_sum}\n"
        f"output_bytes {output_bytes}\n"
        f"output_fnv1a {h}\n"
    )


if __name__ == "__main__":
    main()
