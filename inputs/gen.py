#!/usr/bin/env python3
"""Generate every input file into inputs/data/.

Each inputs/gen_<name>.py module exposes `generate(data_dir: pathlib.Path)`, which writes its
files deterministically. This dispatcher imports them all and calls each one. To keep re-runs
cheap, it records a fingerprint per generator in inputs/data/.manifest.json: the generator's
source hash plus the SHA-256 of every file it wrote. A generator whose source is unchanged and
whose files still have the recorded hashes is skipped. --force regenerates everything.

Usage: gen.py [--force] [--only NAME ...] [--data-dir DIR]
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_DATA = HERE / "data"
MANIFEST = ".manifest.json"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def snapshot(data_dir: Path) -> dict[str, tuple[int, float]]:
    out = {}
    for p in data_dir.rglob("*"):
        if p.is_file() and p.name != MANIFEST:
            st = p.stat()
            out[p.relative_to(data_dir).as_posix()] = (st.st_size, st.st_mtime_ns)
    return out


def load_module(path: Path):
    spec = importlib.util.spec_from_file_location(f"cheby_compare_{path.stem}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def up_to_date(entry: dict | None, src_hash: str, data_dir: Path) -> bool:
    if not entry or entry.get("source") != src_hash or not entry.get("files"):
        return False
    for rel, digest in entry["files"].items():
        p = data_dir / rel
        if not p.is_file() or sha256(p) != digest:
            return False
    return True


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="regenerate even when up to date")
    ap.add_argument("--only", nargs="+", metavar="NAME", help="only these generators (gen_<NAME>.py)")
    ap.add_argument("--data-dir", type=Path, default=DEFAULT_DATA)
    a = ap.parse_args(argv)

    data_dir: Path = a.data_dir.resolve()
    data_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = data_dir / MANIFEST
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, ValueError):
        manifest = {}

    gens = sorted(HERE.glob("gen_*.py"))
    if a.only:
        wanted = {n if n.startswith("gen_") else f"gen_{n}" for n in a.only}
        gens = [g for g in gens if g.stem in wanted]
    if not gens:
        print("no inputs/gen_*.py generators found", file=sys.stderr)
        return 0

    failed = 0
    for g in gens:
        name = g.stem
        src_hash = hashlib.sha256(g.read_bytes()).hexdigest()
        if not a.force and up_to_date(manifest.get(name), src_hash, data_dir):
            print(f"{name}: up to date")
            continue
        before = snapshot(data_dir)
        t0 = time.monotonic()
        try:
            mod = load_module(g)
            if not hasattr(mod, "generate"):
                raise AttributeError(f"{g.name} has no generate(data_dir)")
            mod.generate(data_dir)
        except Exception as e:  # report and go on with the other generators
            print(f"{name}: FAILED: {e!r}", file=sys.stderr)
            failed += 1
            continue
        after = snapshot(data_dir)
        written = sorted(rel for rel, st in after.items() if before.get(rel) != st)
        # A generator that skipped writing (its own up-to-date check) keeps its old file list.
        files = {rel: sha256(data_dir / rel) for rel in written}
        old = (manifest.get(name) or {}).get("files", {})
        for rel in old:
            if rel not in files and (data_dir / rel).is_file():
                files[rel] = sha256(data_dir / rel)
        manifest[name] = {"source": src_hash, "files": files}
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        sizes = ", ".join(f"{rel} ({(data_dir / rel).stat().st_size:,} B)" for rel in sorted(files))
        print(f"{name}: generated in {time.monotonic() - t0:.1f}s: {sizes or 'no files'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
