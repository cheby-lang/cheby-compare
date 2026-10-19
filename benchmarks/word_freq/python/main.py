"""word_freq: counts the words of a file and prints the 20 most frequent."""

import sys
from collections import Counter

TOP = 20


def main() -> None:
    with open(sys.argv[1], "rb") as f:
        text = f.read().decode("ascii")
    counts = Counter(text.split())
    ranked = sorted(counts.items(), key=lambda entry: (-entry[1], entry[0]))
    lines = [f"total {counts.total()}", f"distinct {len(counts)}"]
    lines.extend(f"{count} {word}" for word, count in ranked[:TOP])
    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
