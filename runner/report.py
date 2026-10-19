#!/usr/bin/env python3
"""Turn a results JSON into RESULTS.md, report/index.html and the README summary.

Usage: report.py [results/<file>.json] [--md RESULTS.md] [--html report/index.html]
                 [--readme README.md | --no-readme] [--out-dir DIR] [--benchmarks-dir benchmarks]

Without a results file, the newest results/*.json is used. Cheby's compile and run times are
estimates until M3 (see CONVENTIONS.md, "Measurement"), and every Cheby number says so.

--out-dir DIR writes DIR/RESULTS.md, DIR/report/index.html and DIR/README-results.md (the
summary that would go into the README) and leaves the repository's copies alone, for test runs.

impl.toml keys the report honours (copied into the results by run.py, and read from
benchmarks/<bench>/<lang>/impl.toml when an older results file lacks them):
  comparable = false   the row is shown, tagged "not comparable" with `comparable_note` as a
                       footnote, and left out of geometric means and "fastest" baselines
  known_failure = "…"  shown instead of the raw error when that implementation fails
Library variants (ids with '-', such as rust-tokio) appear only in the benchmarks they
implement and get their own summary table instead of joining the per-language one.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import re
import statistics
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

BENCH_INFO = {
    "binary_trees": ("CPU", "allocation and freeing of many small nodes"),
    "nbody": ("CPU", "floating point on a few records, many steps"),
    "spectral_norm": ("CPU", "floating point over vectors, O(n²) per step"),
    "mandelbrot": ("CPU", "tight float loops, no allocation"),
    "fannkuch_redux": ("CPU", "in-place permutation of a small array"),
    "word_freq": ("data", "reading a file, splitting, hash map counting, sorting"),
    "json_roundtrip": ("data", "parsing, walking and serializing a JSON document"),
    "lru_cache": ("data", "an LRU cache under a pseudo-random access stream"),
    "ping_pong": ("concurrency", "message passing between two lightweight tasks"),
    "spawn_many": ("concurrency", "spawning and joining many short tasks"),
    "prime_sieve": ("concurrency", "a pipeline of filter tasks connected by channels"),
    "hello_world": ("compile speed", "the smallest program: cold compile time and start-up"),
    "compile_large": ("compile speed", "a generated project of many modules: compile-time scaling"),
}
BENCH_ORDER = list(BENCH_INFO)
LANG_ORDER = [
    "cheby", "gleam", "rust", "rust-tokio", "go", "zig", "odin", "cpp", "erlang", "python",
    "java", "typescript", "swift", "csharp", "elixir", "scala", "clojure", "clojure-coreasync",
    "koka", "ocaml", "ocaml-eio", "nim", "ruby",
]
STATUS_TEXT = {
    "timeout": "timeout", "wrong-output": "wrong output", "build-error": "build error",
    "run-error": "run error", "unverified": "no expected output", "error": "error",
    "FAIL": "wrong output",
}
EST = "JIT, estimated split"
WHOLE = "JIT, whole process"
NC = "not comparable"
KNOWN = "known failure"
# Display names of the library variants, used when the results lack a "Base (library)" name.
VARIANT_NAMES = {
    "rust-tokio": "Rust (tokio)",
    "clojure-coreasync": "Clojure (core.async)",
    "ocaml-eio": "OCaml (Eio)",
}
IMPL_KEYS = ("comparable", "comparable_note", "known_failure", "libs", "notes")


def is_variant(lang: str) -> bool:
    return "-" in lang


def variant_base(lang: str) -> str:
    return lang.split("-", 1)[0]


def display_name(lang: str, name: str | None) -> str:
    if is_variant(lang) and (not name or "(" not in name):
        if lang in VARIANT_NAMES:
            return VARIANT_NAMES[lang]
        base, lib = lang.split("-", 1)
        return f"{(name or base).split(' ')[0].capitalize()} ({lib})"
    return name or lang


def n1(st) -> str:
    """' (n=1)' for a timing taken from a single run (a very slow benchmark)."""
    return " (n=1)" if isinstance(st, dict) and st.get("runs") == 1 else ""


def order_key(order):
    return lambda x: ((order.index(x), x) if x in order else (len(order), x))


def is_project(bench: str) -> bool:
    return bench == "compile_large" or bench.endswith("compile_large")


def is_runtime_bench(bench: str) -> bool:
    return not is_project(bench) and bench != "hello_world"


# Run-time means in the summary, one per group. There is no mean over every run-time benchmark:
# the concurrency group compares task runtimes (often against OS threads) and would hide the
# CPU and data results behind it.
RUN_GROUPS = [
    ("cpu", "CPU", {"CPU"}),
    ("data", "Data", {"data"}),
    ("conc", "Concurrency", {"concurrency"}),
    ("cpudata", "CPU + data", {"CPU", "data"}),
]


def run_groups(bench: str) -> list[str]:
    grp = BENCH_INFO.get(bench, ("", ""))[0]
    return [k for k, _, gs in RUN_GROUPS if grp in gs]


# ----------------------------------------------------------------------------------------------
# Formatting


def fmt_time(s) -> str:
    if s is None:
        return "–"
    if s < 0.001:
        return f"{s * 1e3:.2f} ms"
    if s < 0.01:
        return f"{s * 1e3:.1f} ms"
    if s < 1:
        return f"{s * 1e3:.0f} ms"
    if s < 10:
        return f"{s:.2f} s"
    return f"{s:.1f} s"


def fmt_bytes(b) -> str:
    if b is None:
        return "–"
    for unit, scale in (("GB", 1 << 30), ("MB", 1 << 20), ("KB", 1 << 10)):
        if b >= scale:
            v = b / scale
            return f"{v:.1f} {unit}" if v < 100 else f"{v:.0f} {unit}"
    return f"{b} B"


def fmt_ratio(r) -> str:
    if r is None:
        return "–"
    if r < 10:
        return f"{r:.2f}×"
    if r < 100:
        return f"{r:.1f}×"
    return f"{r:.0f}×"


def ok_stats(st) -> dict | None:
    return st if isinstance(st, dict) and "median" in st and "error" not in st else None


def geomean(xs):
    xs = [x for x in xs if x and x > 0]
    return math.exp(statistics.fmean(math.log(x) for x in xs)) if xs else None


# ----------------------------------------------------------------------------------------------
# Model


class Row:
    """One implementation's numbers for one benchmark, with Cheby's estimates applied."""

    def __init__(self, e: dict, versions: dict):
        self.e = e
        self.lang = e["lang"]
        self.name = display_name(self.lang, e.get("name"))
        self.kind = e.get("kind", "")
        self.status = e.get("status", "?")
        self.jit = self.kind == "jit"
        self.variant = is_variant(self.lang)
        self.comparable = e.get("comparable", True) is not False
        self.comparable_note = e.get("comparable_note") or ""
        self.known_failure = e.get("known_failure") or ""
        run = ok_stats(e.get("run"))
        self.whole = run  # the whole process at bench size
        self.n1 = n1(run)  # the bench-size run was timed once (over 60 s)
        # Size-0 benchmarks (hello_world): no split, the whole process is the run time.
        self.no_split = self.jit and bool(e.get("no_split"))
        if self.no_split:
            self.run = run
            self.compile = ok_stats(e.get("compile_estimate"))
            self.compile_warm = None
        elif self.jit:
            self.run = ok_stats(e.get("runtime_estimate"))
            self.compile = ok_stats(e.get("compile_estimate"))
            self.compile_warm = None
        else:
            self.run = run
            self.compile = ok_stats(e.get("compile"))
            # Scala (Bloop) and C# (build server): a second compile time with the server warm.
            self.compile_warm = ok_stats(e.get("compile_warm"))
        self.startup = ok_stats(e.get("startup"))
        self.check = ok_stats(e.get("check"))
        self.rss = e.get("rss_bytes")
        self.artifact = e.get("artifact_bytes")
        self.loc = e.get("loc")
        self.libs = e.get("libs") or []
        self.notes = e.get("notes") or ""
        self.version = versions.get(self.lang, "")

    @property
    def label(self) -> str:
        s = (f"{self.name} ({WHOLE})" if self.no_split
             else f"{self.name} ({EST})" if self.jit else self.name)
        return s if self.comparable else f"{s} ({NC})"

    @property
    def run_value(self):
        return self.run["median"] if self.run else None

    @property
    def fail_text(self) -> str:
        """What a failed row shows: its known_failure tag, or the status."""
        return KNOWN if self.known_failure else STATUS_TEXT.get(self.status, self.status)


def load(path: Path) -> dict:
    return json.loads(path.read_text())


def enrich(data: dict, benchmarks_dir: Path) -> None:
    """Fill impl.toml keys that a results file lacks (one measured before run.py copied them,
    or an entry resumed from an older run) from benchmarks/<bench>/<lang>/impl.toml."""
    cache: dict[Path, dict] = {}
    for e in data.get("entries", {}).values():
        p = benchmarks_dir / e.get("bench", "") / e.get("lang", "") / "impl.toml"
        if p not in cache:
            try:
                cache[p] = tomllib.loads(p.read_text()) if p.is_file() else {}
            except (OSError, tomllib.TOMLDecodeError):
                cache[p] = {}
        for k in IMPL_KEYS:
            if k in cache[p] and not e.get(k):
                e[k] = cache[p][k]
        e["name"] = display_name(e["lang"], e.get("name"))
        # A JIT entry whose bench size is size 0 (hello_world) has no compile/run split: the
        # estimate would be one size-0 run minus another, which is noise. It shows the whole
        # process instead.
        sp = benchmarks_dir / e.get("bench", "") / "sizes.toml"
        if sp not in cache:
            try:
                cache[sp] = tomllib.loads(sp.read_text()) if sp.is_file() else {}
            except (OSError, tomllib.TOMLDecodeError):
                cache[sp] = {}
        zero = cache[sp].get("zero")
        if e.get("kind") == "jit" and zero is not None and e.get("args") == zero:
            e["no_split"] = True


def comparable(e: dict) -> bool:
    return e.get("comparable", True) is not False


def group(data: dict) -> dict[str, list[dict]]:
    by_bench: dict[str, list[dict]] = {}
    for e in data.get("entries", {}).values():
        by_bench.setdefault(e["bench"], []).append(e)
    return {b: by_bench[b] for b in sorted(by_bench, key=order_key(BENCH_ORDER))}


def sorted_rows(rows: list[Row]) -> list[Row]:
    """Fastest first; rows that are not comparable go after all comparable ones."""
    def key(r: Row):
        v = r.run_value if r.run_value is not None else (r.startup or {}).get("median")
        return (not r.comparable, v is None, v if v is not None else 0, order_key(LANG_ORDER)(r.lang))
    return sorted(rows, key=key)


def fastest_run(rows: list[Row]):
    """The relative-to-fastest baseline: the fastest comparable row."""
    return min((r.run_value for r in rows if r.run_value and r.comparable), default=None)


def summary(benches: dict[str, list[dict]], versions: dict) -> list[dict]:
    """Geometric mean of run- and compile-time ratios against Rust, per language. Rows marked
    `comparable = false` are left out (and listed in "excluded"). Library variants get the same
    numbers plus the ratio to their base language, and the report shows them apart."""
    per_lang: dict[str, dict] = {}
    for bench, entries in benches.items():
        if is_project(bench):
            continue
        rows = {e["lang"]: Row(e, versions) for e in entries}
        rust = rows.get("rust")
        if rust and not rust.comparable:
            rust = None
        for lang, r in rows.items():
            s = per_lang.setdefault(lang, {"lang": lang, "name": r.name, "kind": r.kind,
                                           "variant": r.variant, "base": variant_base(lang),
                                           "run": [], "whole": [], "compile": [], "vs_base": [],
                                           "run_by": {k: [] for k, _, _ in RUN_GROUPS},
                                           "whole_by": {k: [] for k, _, _ in RUN_GROUPS},
                                           "benches": [], "excluded": [], "excluded_notes": []})
            if not r.comparable:
                s["excluded"].append(bench)
                if r.comparable_note and r.comparable_note not in s["excluded_notes"]:
                    s["excluded_notes"].append(r.comparable_note)
                continue
            s["benches"].append(bench)
            if r.variant and is_runtime_bench(bench) and r.run_value:
                base = rows.get(variant_base(lang))
                if base and base.comparable and base.run_value:
                    s["vs_base"].append(r.run_value / base.run_value)
            if not rust:
                continue
            if is_runtime_bench(bench) and rust.run_value and r.run_value:
                s["run"].append(r.run_value / rust.run_value)
                for k in run_groups(bench):
                    s["run_by"][k].append(r.run_value / rust.run_value)
                if r.jit and r.whole:
                    s["whole"].append(r.whole["median"] / rust.run_value)
                    for k in run_groups(bench):
                        s["whole_by"][k].append(r.whole["median"] / rust.run_value)
            if rust.compile and r.compile:  # always the cold compile
                s["compile"].append(r.compile["median"] / rust.compile["median"])
    out = []
    for lang in sorted(per_lang, key=order_key(LANG_ORDER)):
        s = per_lang[lang]
        out.append({**s, "run_gm": geomean(s["run"]), "run_n": len(s["run"]),
                    "whole_gm": geomean(s["whole"]), "whole_n": len(s["whole"]),
                    "compile_gm": geomean(s["compile"]), "compile_n": len(s["compile"]),
                    "vs_base_gm": geomean(s["vs_base"]), "vs_base_n": len(s["vs_base"]),
                    "group_gm": {k: geomean(v) for k, v in s["run_by"].items()},
                    "group_n": {k: len(v) for k, v in s["run_by"].items()},
                    "whole_group_gm": {k: geomean(v) for k, v in s["whole_by"].items()},
                    "whole_group_n": {k: len(v) for k, v in s["whole_by"].items()}})
    return out


def main_summary(summ: list[dict]) -> list[dict]:
    return [s for s in summ if not s["variant"]]


def variant_summary(summ: list[dict]) -> list[dict]:
    return [s for s in summ if s["variant"]]


def base_name(summ: list[dict], base: str) -> str:
    return next((s["name"] for s in summ if s["lang"] == base), base)


# ----------------------------------------------------------------------------------------------
# Markdown


def md_table(header: list[str], rows: list[list[str]], align: list[str] | None = None) -> str:
    """A Markdown table padded the way Prettier formats it."""
    align = align or ["l"] * len(header)
    cells = [header] + rows
    widths = [max(3, max(len(c[i]) for c in cells)) for i in range(len(header))]

    def line(r):
        out = []
        for c, w, a in zip(r, widths, align):
            out.append(c.rjust(w) if a == "r" else c.ljust(w))
        return "| " + " | ".join(out) + " |"

    sep = "| " + " | ".join(("-" * (w - 1) + ":") if a == "r" else "-" * w
                            for w, a in zip(widths, align)) + " |"
    return "\n".join([line(header), sep] + [line(r) for r in rows])


def run_cell(r: Row) -> str:
    if r.status != "ok" and not r.run:
        return r.fail_text
    if not r.run:
        return "–"
    s = f"{fmt_time(r.run['median'])} [{fmt_time(r.run['min'])}–{fmt_time(r.run['max'])}]{r.n1}"
    return ("≈ " + s) if r.jit and not r.no_split else s


def rel_cell(r: Row, fastest) -> str:
    if not r.comparable:
        return NC
    return fmt_ratio(r.run_value / fastest) if r.run_value and fastest else "–"


def compile_cell(r: Row) -> str:
    if r.compile:
        return ("≈ " if r.jit else "") + fmt_time(r.compile["median"])
    if r.jit or r.e.get("compile"):
        return "–"  # missing estimate, or the timed build failed
    return "none"  # no compile step (interpreters)


def warm_cell(r: Row) -> str:
    return fmt_time(r.compile_warm["median"]) if r.compile_warm else "–"


def nc_note(name: str, note: str | None) -> str:
    """The footnote of a row marked `comparable = false`: its comparable_note, or a default."""
    return note or (f"{name} is {NC} here: it is shown, but left out of the geometric means "
                    "and the fastest baseline.")


def footnotes(rows: list[Row]) -> list[str]:
    """Lines under a benchmark's table: not-comparable notes, known failures, raw errors."""
    out = []
    for r in rows:
        if not r.comparable:
            out.append(nc_note(r.name, r.comparable_note))
        if r.status != "ok":
            if r.known_failure:
                out.append(f"{r.name}: {KNOWN}: {r.known_failure}")
            elif r.e.get("error"):
                out.append(f"{r.name}: {STATUS_TEXT.get(r.status, r.status)}: "
                           f"{r.e['error'].splitlines()[0]}")
        if r.n1:
            out.append(f"{r.name}: the bench-size run takes over 60 s, so it was timed once (n=1).")
    return out


def summary_md(summ: list[dict]) -> str:
    rows = []
    main = main_summary(summ)
    def cells(gm, n):
        return [fmt_ratio(gm[k]) + (f" ({n[k]})" if n[k] else "") for k, _, _ in RUN_GROUPS]

    for s in main:
        name = s["name"] + (f" ({EST})" if s["kind"] == "jit" else "")
        rows.append([name, s["kind"]] + cells(s["group_gm"], s["group_n"])
                    + [fmt_ratio(s["compile_gm"]) + (f" ({s['compile_n']})" if s["compile_n"] else "")])
        if s["kind"] == "jit" and s["whole_n"]:
            rows.append([f"{s['name']} (whole process: compile + run)", s["kind"]]
                        + cells(s["whole_group_gm"], s["whole_group_n"]) + ["–"])
    table = md_table(["Language", "Kind"] + [f"{t} run vs Rust" for _, t, _ in RUN_GROUPS]
                     + ["Compile vs Rust (cold)"], rows, ["l", "l"] + ["r"] * (len(RUN_GROUPS) + 1))
    text = (table + "\n\nGeometric mean of the per-benchmark ratio to Rust, with the number of "
            "benchmarks in parentheses. Below 1× is faster than Rust. Run time is averaged per "
            "group (CPU, data, concurrency, and CPU and data together) and never over all three: "
            "the concurrency benchmarks compare task runtimes, often lightweight tasks against "
            "Rust's OS threads, and one mean over everything would let them hide the CPU and data "
            "results. Compile time covers every benchmark with a compile step and is the cold "
            "compile (no build server; Scala's and C#'s warm compile is in the per-benchmark "
            "tables).")
    excl = [s for s in main if s["excluded"]]
    if excl:
        text += " Rows marked not comparable are left out: " + "; ".join(
            f"{s['name']} ({', '.join(s['excluded'])})" for s in excl) + "."
        notes = [n for s in excl for n in s["excluded_notes"]]
        if notes:
            text += "\n\n" + "\n".join(f"- {n}" for n in dict.fromkeys(notes))
    var = variant_summary(summ)
    if var:
        vrows = []
        for s in var:
            base = base_name(summ, s["base"])
            vrows.append([s["name"], ", ".join(s["benches"]) or "–",
                          fmt_ratio(s["run_gm"]) + (f" ({s['run_n']})" if s["run_n"] else ""),
                          fmt_ratio(s["vs_base_gm"]) + (f" ({s['vs_base_n']})" if s["vs_base_n"] else "")
                          + (f" vs {base}" if s["vs_base_n"] else "")])
        text += ("\n\nLibrary variants (a well-known concurrency library instead of the standard "
                 "one) cover only the benchmarks listed, so they are kept out of the table above:\n\n"
                 + md_table(["Variant", "Benchmarks", "Run time vs Rust", "Run time vs base language"],
                            vrows, ["l", "l", "r", "r"]))
    return text


def bench_md(bench: str, entries: list[dict], versions: dict, notes: str | None) -> str:
    grp, what = BENCH_INFO.get(bench, ("", ""))
    out = [f"## {bench}", ""]
    if what:
        out += [f"_{grp}: {what}._", ""]
    if is_project(bench):
        out.append(project_md(entries, versions))
        if notes:
            out += ["", "### Notes", "", notes.strip()]
        return "\n".join(out) + "\n"
    rows = sorted_rows([Row(e, versions) for e in entries])
    fastest = fastest_run(rows)
    has_warm = any(r.compile_warm for r in rows)
    args = next((e.get("args") for e in entries if e.get("args")), None)
    if args:
        out += [f"Bench size arguments: `{' '.join(args)}`.", ""]
    table = []
    for r in rows:
        table.append(
            [r.label, run_cell(r), rel_cell(r, fastest), compile_cell(r)]
            + ([warm_cell(r)] if has_warm else [])
            + [fmt_time(r.startup["median"]) if r.startup else "–",
               fmt_bytes(r.rss), fmt_bytes(r.artifact), str(r.loc) if r.loc is not None else "–",
               ", ".join(r.libs) or "–"])
    header = (["Language", "Run time (median [min–max])", "vs fastest", "Compile (cold)"]
              + (["Compile (warm server)"] if has_warm else [])
              + ["Start-up", "Peak RSS", "Artifact", "LOC", "Libraries"])
    out.append(md_table(header, table, ["l"] + ["r"] * (len(header) - 2) + ["l"]))
    if has_warm:
        out += ["", "Warm compile: the build server (Scala's Bloop, the .NET build server) is "
                "running and warmed up by three builds; cold compile, the main number, has no "
                "server."]
    for line in footnotes(rows):
        out += ["", line]
    for r in rows:
        if r.jit:
            bits = []
            if r.whole:
                bits.append(f"the whole process at bench size took {fmt_time(r.whole['median'])}")
            if r.check:
                bits.append(f"`cheby check` (front end only) took {fmt_time(r.check['median'])}")
            if r.no_split:
                out += ["", f"{r.name}: the bench size is size 0, so there is no compile/run "
                        "split; the run time is the whole process, JIT compile included"
                        + (f". `cheby check` (front end only) took {fmt_time(r.check['median'])}"
                           if r.check else "") + "."]
            elif bits:
                out += ["", f"{r.name}: " + "; ".join(bits) + ". Its run and compile times are "
                        "estimates: compile = median run at size 0, run = whole process minus that."]
            if r.run and r.run_value is not None and r.e.get("runtime_estimate", {}).get("clamped"):
                out += ["", f"{r.name}: the bench-size run was not slower than the size-0 run, so "
                        "the run-time estimate is clamped to 0."]
    if notes:
        out += ["", "### Notes", "", notes.strip()]
    return "\n".join(out) + "\n"


def project_sizes(entries: list[dict]) -> list[str]:
    sizes: list[str] = []
    for e in entries:
        for s in e.get("sizes", {}):
            if s not in sizes:
                sizes.append(s)
    return sizes


def project_label(e: dict) -> str:
    name = e.get("name") or e["lang"]
    if e.get("kind") == "jit":
        name += " (JIT run, estimate)"
    elif e.get("kind") == "interpreter":
        name += " (load and run)"
    if not comparable(e):
        name += f" ({NC})"
    return name


def project_fail_text(e: dict, v: dict) -> str:
    return KNOWN if e.get("known_failure") else STATUS_TEXT.get(v.get("status"), v.get("status"))


def project_warm_sizes(entries: list[dict], sizes: list[str]) -> list[str]:
    return [s for s in sizes
            if any(ok_stats((e.get("sizes", {}).get(s) or {}).get("compile_warm")) for e in entries)]


def project_md(entries: list[dict], versions: dict) -> str:
    sizes = project_sizes(entries)
    warm_sizes = project_warm_sizes(entries, sizes)
    rows = []
    notes = []
    for e in sorted(entries, key=lambda e: (not comparable(e), order_key(LANG_ORDER)(e["lang"]))):
        row = [project_label(e)]
        failed = []
        for s in sizes:
            v = e.get("sizes", {}).get(s)
            st = ok_stats((v or {}).get("compile"))
            if not v:
                row.append("–")
            elif v.get("status") != "ok":
                row.append(project_fail_text(e, v))
                failed.append((s, v))
            else:
                row.append((("≈ " if e.get("kind") == "jit" else "") + fmt_time(st["median"])
                            + n1(st)) if st else "–")
            if s in warm_sizes:
                w = ok_stats((v or {}).get("compile_warm"))
                row.append(fmt_time(w["median"]) if w else "–")
        rows.append(row)
        name = e.get("name") or e["lang"]
        if not comparable(e):
            notes.append(nc_note(name, e.get("comparable_note")))
        if failed and e.get("known_failure"):
            notes.append(f"{name}: {KNOWN}: {e['known_failure']}")
        elif failed:
            for s, v in failed:
                err = (v.get("error") or "").strip().splitlines()
                notes.append(f"{name}, size {s}: {STATUS_TEXT.get(v.get('status'), v.get('status'))}"
                             + (f": {err[0]}" if err else ""))
    loc_line = []
    for e in entries:
        for s, v in e.get("sizes", {}).items():
            if v.get("loc") is not None:
                loc_line.append(f"{e['lang']} {s}: {v.get('files', '?')} files, {v['loc']} lines")
    header = ["Language"]
    for s in sizes:
        header.append(f"Compile (cold), size {s}")
        if s in warm_sizes:
            header.append(f"Compile (warm server), size {s}")
    text = md_table(header, rows, ["l"] + ["r"] * (len(header) - 1))
    text += ("\n\nCompiled languages: a clean build of the generated project, cold (no build "
             "server). Cheby: a `cheby run` of the project, which compiles every module (an "
             "estimate). Interpreters: the time to load and run everything.")
    if warm_sizes:
        text += (" Warm server: Scala's Bloop or the .NET build server running and warmed up by "
                 "three builds.")
    if notes:
        text += "\n\n" + "\n".join(f"- {n}" for n in notes)
    if loc_line:
        text += "\n\nProject sizes: " + "; ".join(loc_line) + "."
    return text


def machine_md(data: dict) -> str:
    m = data.get("machine", {})
    mem = fmt_bytes(m.get("memory_bytes")) if m.get("memory_bytes") else "?"
    cores = m.get("cores", "?")
    if m.get("perf_cores"):
        cores = f"{cores} ({m['perf_cores']} performance + {m.get('efficiency_cores', 0)} efficiency)"
    lines = [
        f"- Machine: {m.get('cpu', '?')}, {cores} cores, {mem}, {m.get('os', m.get('platform', '?'))}",
        f"- Measured: {data.get('created', '?')} to {data.get('updated', '?')}"
        + (" (quick mode: 3 runs, no warm-up; smoke test only)" if data.get("quick") else ""),
        f"- Tools: {m.get('hyperfine', 'hyperfine')}, Python {m.get('python', '?')}",
    ]
    ch = data.get("cheby", {})
    if ch.get("commit"):
        lines.append(f"- Cheby: commit {ch['commit']} of the reference implementation")
    return "\n".join(lines)


def versions_md(data: dict) -> str:
    v = data.get("versions", {})
    rows = [[lang, v[lang] or "–"] for lang in sorted(v, key=order_key(LANG_ORDER))]
    return md_table(["Language", "Version"], rows)


def write_md(data: dict, benches, summ, notes: dict, path: Path):
    parts = [
        "# Results", "",
        "Generated by `runner/report.py` from the measured JSON. Do not edit by hand.", "",
        machine_md(data), "",
        "Cheby compiles and runs in one step until its milestone M3. Its compile time is "
        "estimated as the median run at size 0 of the same program, whose JIT compiles every "
        "function before `main` runs, and its run time as the bench-size run minus that. "
        f"Rows marked \"{EST}\" and values marked ≈ are these estimates. See "
        "[CONVENTIONS.md](CONVENTIONS.md#measurement) and the README's Methodology section.", "",
        "## Summary", "", summary_md(summ), "",
    ]
    for bench, entries in benches.items():
        parts.append(bench_md(bench, entries, data.get("versions", {}), notes.get(bench)))
    parts += ["## Toolchains", "", versions_md(data), ""]
    path.write_text("\n".join(parts))


def update_readme(readme: Path, summ, data: dict):
    if not readme.is_file():
        return False
    text = readme.read_text()
    start, end = "<!-- results:start -->", "<!-- results:end -->"
    if start not in text or end not in text:
        return False
    m = data.get("machine", {})
    body = (f"\n_Measured on {m.get('cpu', '?')}, {m.get('os', '?')}, "
            f"{(data.get('updated') or '')[:10]}"
            + (", quick mode" if data.get("quick") else "")
            + ". Full tables: [RESULTS.md](RESULTS.md); charts: "
              "[report/index.html](report/index.html)._\n\n" + summary_md(summ) + "\n")
    new = text[: text.index(start) + len(start)] + body + text[text.index(end):]
    readme.write_text(new)
    return True


# ----------------------------------------------------------------------------------------------
# HTML


def mini_markdown(text: str) -> str:
    """Headings, paragraphs, '-' lists, `code`, **bold**, *em* and [links](url)."""
    def inline(s: str) -> str:
        s = html.escape(s, quote=False)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"(?<![*\w])\*([^*]+)\*(?!\*)", r"<em>\1</em>", s)
        s = re.sub(r"(?<!\w)_([^_]+)_(?!\w)", r"<em>\1</em>", s)
        s = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
                   lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>', s)
        return s

    out, para, items = [], [], []

    def flush():
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()
        if items:
            out.append("<ul>" + "".join(f"<li>{inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for line in text.splitlines():
        s = line.strip()
        if not s:
            flush()
        elif s.startswith("#"):
            flush()
            out.append(f"<h4>{inline(s.lstrip('#').strip())}</h4>")
        elif re.match(r"^[-*] ", s):
            if para:
                flush()
            items.append(s[2:])
        elif items and line.startswith(("  ", "\t")):
            items[-1] += " " + s
        else:
            if items:
                flush()
            para.append(s)
    flush()
    return "\n".join(out)


def e(s) -> str:
    return html.escape(str(s))


def bar_chart(bars: list[dict], title: str, unit_fmt, log: bool, ref: float | None = None,
              ref_label: str = "") -> str:
    """Horizontal bars as inline SVG. Each bar: label, value, tip, hl, nc (not comparable:
    drawn outlined and muted), ghost (optional end value drawn as an outlined extension), note
    (text after the value). Bar lengths are percentages, so the chart reflows to any width while
    the text stays at its size."""
    vals = [b["value"] for b in bars if b.get("value")] + [b["ghost"] for b in bars if b.get("ghost")]
    if ref:
        vals.append(ref)
    if not vals:
        return ""
    vmax = max(vals)
    vmin = min(vals)
    span = 68.0  # percent of the width the longest bar takes, the rest is for its value label
    if log:
        lo = math.log10(vmin) - max(0.3, 0.12 * (math.log10(vmax) - math.log10(vmin)))
        hi = math.log10(vmax)

        def pct(v):
            return span * (math.log10(v) - lo) / (hi - lo) if hi > lo else span
    else:
        def pct(v):
            return span * v / vmax if vmax > 0 else 0
    row_h, bar_h, top = 38, 12, 6
    height = top + row_h * len(bars) + 4
    parts = [f'<svg class="chart" width="100%" height="{height}" role="img" '
             f'aria-label="{e(title)}" xmlns="http://www.w3.org/2000/svg">']
    if ref:
        x = pct(ref)
        parts.append(f'<line class="ref" x1="{x:.2f}%" x2="{x:.2f}%" y1="{top}" y2="{height - 2}"/>')
    for i, b in enumerate(bars):
        y = top + i * row_h
        cls = " ".join(c for c, on in (("hl", b.get("hl")), ("nc", b.get("nc"))) if on)
        parts.append(f'<g class="row {cls}"><title>{e(b.get("tip") or b["label"])}</title>')
        parts.append(f'<rect class="hit" x="0" y="{y}" width="100%" height="{row_h}"/>')
        parts.append(f'<text class="lbl" x="0" y="{y + 13}">{e(b["label"])}</text>')
        by = y + 19
        if b.get("value"):
            w = max(pct(b["value"]), 0.4)
            parts.append(f'<rect class="bar" x="0" y="{by}" width="{w:.2f}%" height="{bar_h}" rx="3"/>')
            end = w
            if b.get("ghost") and b["ghost"] > b["value"]:
                g = pct(b["ghost"])
                parts.append(f'<rect class="ghost" x="{w:.2f}%" y="{by + 0.5}" width="{max(g - w, 0.2):.2f}%" '
                             f'height="{bar_h - 1}" rx="3"/>')
                end = g
            txt = unit_fmt(b["value"]) + (f"  {b['note']}" if b.get("note") else "")
            parts.append(f'<text class="val" x="{end:.2f}%" dx="6" y="{by + 10}">{e(txt)}</text>')
        else:
            parts.append(f'<text class="val miss" x="0" y="{by + 10}">{e(b.get("note") or "–")}</text>')
        parts.append("</g>")
    parts.append("</svg>")
    return "".join(parts)


def chart_pair(cid: str, title: str, bars, fmt, ref=None, ref_label="", default_log=True) -> str:
    """Linear and log versions of one chart, switched with a CSS-only toggle."""
    lin = bar_chart(bars, title, fmt, False, ref, ref_label)
    lg = bar_chart(bars, title, fmt, True, ref, ref_label)
    if not lin:
        return ""
    return (f'<figure class="fig"><div class="figbar"><figcaption>{e(title)}</figcaption>'
            f'<div class="toggle" role="radiogroup" aria-label="Scale">'
            f'<input type="radio" name="{cid}" id="{cid}-log" {"checked" if default_log else ""}>'
            f'<label for="{cid}-log">log</label>'
            f'<input type="radio" name="{cid}" id="{cid}-lin" {"" if default_log else "checked"}>'
            f'<label for="{cid}-lin">linear</label></div></div>'
            f'<div class="v-log">{lg}</div><div class="v-lin">{lin}</div></figure>')


def html_table(header, rows, num_cols=()) -> str:
    th = "".join(f'<th class="{"n" if i in num_cols else ""}">{e(h)}</th>' for i, h in enumerate(header))
    trs = []
    for r in rows:
        cls = ' class="hl"' if r[0].startswith("Cheby") else ""
        tds = "".join(f'<td class="{"n" if i in num_cols else ""}">{e(c)}</td>' for i, c in enumerate(r))
        trs.append(f"<tr{cls}>{tds}</tr>")
    return f'<div class="tw"><table><thead><tr>{th}</tr></thead><tbody>{"".join(trs)}</tbody></table></div>'


def run_bar(r: Row, fastest=None) -> dict:
    tip_bits = [r.label]
    if r.run:
        tip_bits.append(f"run {fmt_time(r.run['median'])} (min {fmt_time(r.run['min'])}, "
                        f"max {fmt_time(r.run['max'])}){r.n1}")
    if r.jit and r.whole and not r.no_split:
        tip_bits.append(f"whole process {fmt_time(r.whole['median'])}, of which ≈ "
                        f"{fmt_time(r.compile['median']) if r.compile else '?'} compile")
    if not r.comparable and r.comparable_note:
        tip_bits.append(r.comparable_note)
    if r.status != "ok" and r.known_failure:
        tip_bits.append(f"{KNOWN}: {r.known_failure}")
    if not r.run_value:
        return {"label": r.label, "value": None, "hl": r.jit, "nc": not r.comparable,
                "note": r.fail_text if r.status != "ok" else "–",
                "tip": " · ".join(tip_bits)}
    notes = (["est."] if r.jit and not r.no_split else []) + (["n=1"] if r.n1 else [])
    if r.comparable and fastest and r.run_value == fastest:
        notes.append("fastest")
    if not r.comparable:
        notes.append(NC)
    return {"label": r.label, "value": r.run_value, "hl": r.jit, "nc": not r.comparable,
            "ghost": r.whole["median"] if r.jit and r.whole and not r.no_split else None,
            "note": " ".join(notes), "tip": " · ".join(tip_bits)}


def benches_n(n: int) -> str:
    """The count after a summary bar; "n=" is kept for the number of timed runs."""
    return f"{n} benchmark" + ("" if n == 1 else "s")


def note_html(text: str) -> str:
    return f'<p class="note">{e(text)}</p>'


def write_html(data: dict, benches, summ, notes: dict, path: Path):
    versions = data.get("versions", {})
    sections = []
    nav = []
    # Summary: languages only; library variants get their own table below.
    allsumm, summ = summ, main_summary(summ)
    group_bars = {}
    for k, title, _ in RUN_GROUPS:
        sb = []
        for s in sorted([s for s in summ if s["group_gm"][k]], key=lambda s: s["group_gm"][k]):
            jit = s["kind"] == "jit"
            gm, n = s["group_gm"][k], s["group_n"][k]
            sb.append({"label": s["name"] + (f" ({EST})" if jit else ""), "value": gm,
                       "hl": jit, "ghost": s["whole_group_gm"][k] if jit else None,
                       "note": benches_n(n) + (" est." if jit else ""),
                       "tip": f"{s['name']}: {title} run time, geometric mean {fmt_ratio(gm)} of "
                              f"Rust over {benches_n(n)}"})
        group_bars[k] = (title, sb)
    cb = []
    for s in sorted([s for s in summ if s["compile_gm"]], key=lambda s: s["compile_gm"]):
        jit = s["kind"] == "jit"
        cb.append({"label": s["name"] + (f" ({EST})" if jit else ""), "value": s["compile_gm"],
                   "hl": jit, "note": benches_n(s["compile_n"]),
                   "tip": f"{s['name']}: compile time {fmt_ratio(s['compile_gm'])} of Rust's"})
    srows = []
    for s in summ:
        srows.append([s["name"] + (f" ({EST})" if s["kind"] == "jit" else ""), s["kind"]]
                     + [fmt_ratio(s["group_gm"][k]) for k, _, _ in RUN_GROUPS]
                     + [fmt_ratio(s["compile_gm"]), str(s["compile_n"])])
        if s["kind"] == "jit" and s["whole_n"]:
            srows.append([f"{s['name']} (whole process)", s["kind"]]
                         + [fmt_ratio(s["whole_group_gm"][k]) for k, _, _ in RUN_GROUPS]
                         + ["–", "–"])
    extra = []
    excl = [s for s in summ if s["excluded"]]
    if excl:
        extra.append(note_html("Rows marked not comparable are shown in their benchmarks but left "
                               "out of these means: " + "; ".join(
                                   f"{s['name']} ({', '.join(s['excluded'])})" for s in excl) + "."))
        for n in dict.fromkeys(n for s in excl for n in s["excluded_notes"]):
            extra.append(note_html(n))
    var = variant_summary(allsumm)
    if var:
        vrows = [[s["name"], ", ".join(s["benches"]) or "–", fmt_ratio(s["run_gm"]), str(s["run_n"]),
                  fmt_ratio(s["vs_base_gm"]), base_name(allsumm, s["base"]), str(s["vs_base_n"])]
                 for s in var]
        extra.append("<h4>Library variants</h4>"
                     + note_html("A well-known concurrency library instead of the standard one. "
                                 "They cover only the benchmarks listed, so they are kept out of "
                                 "the per-language means above.")
                     + html_table(["Variant", "Benchmarks", "Run vs Rust", "n", "Run vs base",
                                   "Base", "n"], vrows, {2, 3, 4, 6}))
    nav.append('<a href="#summary">Summary</a>')
    sections.append(
        '<section id="summary"><h2>Summary</h2>'
        '<p class="sub">Geometric mean of each language\'s per-benchmark ratio to Rust. '
        'Shorter is faster; the line marks Rust (1×). Run time is averaged per group and never '
        'over all of them: the concurrency benchmarks compare task runtimes, often lightweight '
        'tasks against Rust\'s OS threads, and one mean over everything would hide the CPU and '
        'data results. Compile time is the cold compile (no build server); Scala\'s and C#\'s '
        'warm compile is in the benchmark tables.</p>'
        + "".join(chart_pair(f"c-sum-run-{k}", f"{title} run time vs Rust (geometric mean)", sb,
                             fmt_ratio, 1.0, "Rust")
                  for k, (title, sb) in group_bars.items())
        + chart_pair("c-sum-comp", "Cold compile time vs Rust (geometric mean)", cb, fmt_ratio, 1.0, "Rust")
        + html_table(["Language", "Kind"] + [f"{t} vs Rust" for _, t, _ in RUN_GROUPS]
                     + ["Compile (cold) vs Rust", "n"], srows,
                     set(range(2, 2 + len(RUN_GROUPS) + 2)))
        + "".join(extra)
        + "</section>")

    for bench, entries in benches.items():
        grp, what = BENCH_INFO.get(bench, ("", ""))
        nav.append(f'<a href="#{e(bench)}">{e(bench)}</a>')
        body = [f'<section id="{e(bench)}"><h2>{e(bench)}</h2>']
        if what:
            body.append(f'<p class="sub"><span class="tag">{e(grp)}</span> {e(what)}</p>')
        if is_project(bench):
            sizes = project_sizes(entries)
            for s in sizes:
                bars = []
                for en in entries:
                    v = en.get("sizes", {}).get(s) or {}
                    st = ok_stats(v.get("compile"))
                    warm = ok_stats(v.get("compile_warm"))
                    jit = en.get("kind") == "jit"
                    nc = not comparable(en)
                    lbl = (en.get("name") or en["lang"]) + (" (JIT run, est.)" if jit else
                                                           " (load + run)" if en.get("kind") == "interpreter" else "")
                    if nc:
                        lbl += f" ({NC})"
                    if st:
                        note = " ".join(x for x in (n1(st).strip(" ()"),
                                                    f"warm {fmt_time(warm['median'])}" if warm else "",
                                                    NC if nc else "") if x)
                    elif v.get("status") and v.get("status") != "ok":
                        note = project_fail_text(en, v)
                    else:
                        note = "not measured"
                    tip = f"{lbl}: {fmt_time(st['median']) if st else note}"
                    if warm:
                        tip += f", warm server {fmt_time(warm['median'])}"
                    if v.get("loc"):
                        tip += f", {v.get('files')} files, {v.get('loc')} lines"
                    if not st and en.get("known_failure"):
                        tip += f" · {en['known_failure']}"
                    bars.append({"label": lbl, "value": st["median"] if st else None, "hl": jit,
                                 "nc": nc, "note": note, "tip": tip})
                bars.sort(key=lambda b: (bool(b.get("nc")), b["value"] is None, b["value"] or 0))
                args = next((en["sizes"][s].get("args") for en in entries if s in en.get("sizes", {})), [])
                body.append(chart_pair(f"c-{bench}-{s}", f"Compile time, size {s} ({' '.join(args)})",
                                       bars, fmt_time))
            md = project_md(entries, versions)
            if "\n\n" in md:
                body.append('<div class="sub">' + mini_markdown(md.split("\n\n", 1)[1]) + "</div>")
        else:
            rows = sorted_rows([Row(x, versions) for x in entries])
            args = next((x.get("args") for x in entries if x.get("args")), None)
            if args:
                body.append(f'<p class="sub">Bench size: <code>{e(" ".join(args))}</code></p>')
            fastest = fastest_run(rows)
            if any(r.run_value for r in rows) or any(r.status != "ok" for r in rows):
                body.append(chart_pair(f"c-{bench}-run", "Run time (median)",
                                       [run_bar(r, fastest) for r in rows], fmt_time))
            comp = [r for r in rows if r.compile]
            if comp:
                comp.sort(key=lambda r: (not r.comparable, r.compile["median"]))
                body.append(chart_pair(f"c-{bench}-comp", "Compile time (median, cold)", [
                    {"label": r.label, "value": r.compile["median"], "hl": r.jit, "nc": not r.comparable,
                     "note": " ".join(x for x in ("est." if r.jit else "",
                                                  f"warm {fmt_time(r.compile_warm['median'])}"
                                                  if r.compile_warm else "") if x),
                     "tip": f"{r.label}: cold {fmt_time(r.compile['median'])}"
                            + (f", warm server {fmt_time(r.compile_warm['median'])}" if r.compile_warm else "")}
                    for r in comp], fmt_time))
            if bench == "hello_world" and any(r.startup for r in rows):
                st = sorted([r for r in rows if r.startup], key=lambda r: (not r.comparable, r.startup["median"]))
                body.append(chart_pair(f"c-{bench}-start", "Start-up (median run at size 0)", [
                    {"label": r.label, "value": r.startup["median"], "hl": r.jit, "nc": not r.comparable,
                     "tip": f"{r.label}: {fmt_time(r.startup['median'])}"} for r in st], fmt_time))
            has_warm = any(r.compile_warm for r in rows)
            trs = []
            for r in rows:
                trs.append([r.label, run_cell(r), rel_cell(r, fastest), compile_cell(r)]
                           + ([warm_cell(r)] if has_warm else [])
                           + [fmt_time(r.startup["median"]) if r.startup else "–",
                              fmt_bytes(r.rss), fmt_bytes(r.artifact),
                              str(r.loc) if r.loc is not None else "–", ", ".join(r.libs) or "–"])
            header = (["Language", "Run time (median [min–max])", "vs fastest", "Compile (cold)"]
                      + (["Compile (warm server)"] if has_warm else [])
                      + ["Start-up", "Peak RSS", "Artifact", "LOC", "Libraries"])
            body.append(html_table(header, trs, set(range(1, len(header) - 1))))
            if has_warm:
                body.append(note_html("Warm compile: the build server (Scala's Bloop, the .NET build "
                                      "server) is running and warmed up by three builds. Cold "
                                      "compile, the main number, has no server."))
            for line in footnotes(rows):
                body.append(note_html(line))
            for r in rows:
                if r.jit and (r.whole or r.check):
                    bits = []
                    if r.whole:
                        bits.append(f"whole process at bench size {fmt_time(r.whole['median'])}")
                    if r.compile:
                        bits.append(f"estimated compile {fmt_time(r.compile['median'])} (median run at size 0)")
                    if r.check:
                        bits.append(f"<code>cheby check</code> {fmt_time(r.check['median'])}")
                    body.append(f'<p class="note"><strong>{e(r.name)}:</strong> ' + "; ".join(
                        b if "<code>" in b else e(b) for b in bits) + ".</p>")
        if notes.get(bench):
            body.append('<div class="notes">' + mini_markdown(notes[bench]) + "</div>")
        body.append("</section>")
        sections.append("".join(body))

    vrows = [[lang, versions[lang]] for lang in sorted(versions, key=order_key(LANG_ORDER))]
    nav.append('<a href="#toolchains">Toolchains</a>')
    sections.append('<section id="toolchains"><h2>Toolchains</h2>'
                    + html_table(["Language", "Version"], vrows) + "</section>")

    m = data.get("machine", {})
    meta = (f"{e(m.get('cpu', '?'))} · {e(m.get('cores', '?'))} cores · "
            f"{e(fmt_bytes(m.get('memory_bytes')))} · {e(m.get('os', '?'))} · "
            f"{e((data.get('updated') or '')[:10])}"
            + (" · <strong>quick mode (smoke test)</strong>" if data.get("quick") else ""))
    page = PAGE.replace("{{META}}", meta).replace("{{NAV}}", " ".join(nav)) \
               .replace("{{SECTIONS}}", "\n".join(sections)).replace("{{EST}}", e(EST))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(page)


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Cheby Compare Results</title>
<style>
:root {
  color-scheme: light;
  --page: #f9f9f7; --surface: #fcfcfb; --ink: #0b0b0b; --ink2: #52514e; --muted: #6f6d67;
  --grid: #e1e0d9; --axis: #c3c2b7; --border: rgba(11,11,11,0.10);
  --bar: #898781; --hl: #2a78d6; --hlwash: rgba(42,120,214,0.08); --hover: rgba(11,11,11,0.04);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --page: #0d0d0d; --surface: #1a1a19; --ink: #f0efec; --ink2: #c3c2b7; --muted: #9a988f;
    --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
    --bar: #6a6963; --hl: #3987e5; --hlwash: rgba(57,135,229,0.14); --hover: rgba(255,255,255,0.05);
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --page: #0d0d0d; --surface: #1a1a19; --ink: #f0efec; --ink2: #c3c2b7; --muted: #9a988f;
  --grid: #2c2c2a; --axis: #383835; --border: rgba(255,255,255,0.10);
  --bar: #6a6963; --hl: #3987e5; --hlwash: rgba(57,135,229,0.14); --hover: rgba(255,255,255,0.05);
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--page); color: var(--ink);
  font: 15px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 920px; margin: 0 auto; padding: 24px 16px 64px; }
h1 { font-size: 26px; margin: 8px 0 4px; }
h2 { font-size: 20px; margin: 0 0 4px; }
h4 { margin: 12px 0 4px; font-size: 15px; }
p { margin: 8px 0; }
a { color: var(--hl); }
code { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; }
.meta, .sub { color: var(--ink2); }
.callout { border-left: 3px solid var(--hl); background: var(--hlwash); padding: 10px 14px;
  border-radius: 0 6px 6px 0; margin: 16px 0; }
nav { display: flex; flex-wrap: wrap; gap: 6px 12px; margin: 16px 0 8px; font-size: 14px; }
section { background: var(--surface); border: 1px solid var(--border); border-radius: 10px;
  padding: 18px 16px; margin: 18px 0; }
.tag { display: inline-block; font-size: 12px; padding: 0 7px; border-radius: 9px;
  border: 1px solid var(--axis); color: var(--ink2); margin-right: 4px; }
.fig { margin: 16px 0; }
.figbar { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; flex-wrap: wrap; }
figcaption { font-weight: 600; font-size: 14px; }
.toggle { display: inline-flex; border: 1px solid var(--axis); border-radius: 6px; overflow: hidden; font-size: 12px; }
.toggle input { position: absolute; opacity: 0; pointer-events: none; }
.toggle label { padding: 2px 10px; cursor: pointer; color: var(--ink2); }
.toggle input:checked + label { background: var(--hover); color: var(--ink); font-weight: 600; }
.toggle input:focus-visible + label { outline: 2px solid var(--hl); outline-offset: -2px; }
.v-lin { display: none; }
.fig:has(input[id$="-lin"]:checked) .v-lin { display: block; }
.fig:has(input[id$="-lin"]:checked) .v-log { display: none; }
svg.chart { display: block; overflow: visible; margin-top: 6px; }
svg.chart text { font-size: 12.5px; fill: var(--ink2); }
svg.chart .lbl { fill: var(--ink); }
svg.chart .row.hl .lbl { font-weight: 700; }
svg.chart .val { fill: var(--ink2); font-variant-numeric: tabular-nums; }
svg.chart .miss { fill: var(--muted); font-style: italic; }
svg.chart .bar { fill: var(--bar); }
svg.chart .row.hl .bar { fill: var(--hl); }
svg.chart .row.nc .bar { fill: none; stroke: var(--bar); stroke-width: 1; stroke-dasharray: 3 2; }
svg.chart .row.nc .lbl { fill: var(--muted); font-style: italic; }
svg.chart .ghost { fill: none; stroke: var(--hl); stroke-width: 1; stroke-dasharray: none; }
svg.chart .hit { fill: transparent; }
svg.chart .row:hover .hit { fill: var(--hover); }
svg.chart .ref { stroke: var(--axis); stroke-width: 1; }
svg.chart .reflbl { fill: var(--muted); font-size: 11px; }
.tw { overflow-x: auto; margin: 12px 0; }
table { border-collapse: collapse; font-size: 13px; width: 100%; }
th, td { padding: 5px 8px; border-bottom: 1px solid var(--grid); text-align: left; white-space: nowrap; }
th { color: var(--ink2); font-weight: 600; }
td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
tr.hl td { background: var(--hlwash); }
tr.hl td:first-child { font-weight: 700; }
.note { font-size: 14px; color: var(--ink2); }
.notes { border-top: 1px solid var(--grid); margin-top: 12px; padding-top: 4px; font-size: 14px; }
@media (max-width: 520px) { svg.chart text { font-size: 11.5px; } section { padding: 14px 12px; } }
</style>
</head>
<body>
<main>
<h1>Cheby compared</h1>
<p class="meta">{{META}}</p>
<div class="callout"><strong>Cheby numbers are estimates.</strong> Cheby only has a JIT until its
milestone M3, so compile and run happen in one process. Compile time is estimated as the median
run at size 0 of the same program (the JIT compiles every function <code>main</code> reaches before
it runs), and run time as the bench-size run minus that. Rows tagged “{{EST}}” use this split; in
run-time charts, the outlined part of Cheby's bar is the estimated compile time, so the full
length is the whole process.</div>
<nav>{{NAV}}</nav>
{{SECTIONS}}
<p class="meta">Generated by runner/report.py. Hover a bar for details; each chart switches
between log and linear scale.</p>
</main>
</body>
</html>
"""


# ----------------------------------------------------------------------------------------------


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("results", nargs="?", type=Path)
    ap.add_argument("--md", type=Path, default=ROOT / "RESULTS.md")
    ap.add_argument("--html", type=Path, default=ROOT / "report" / "index.html")
    ap.add_argument("--readme", type=Path, default=ROOT / "README.md")
    ap.add_argument("--no-readme", action="store_true", help="do not refresh the README summary")
    ap.add_argument("--out-dir", type=Path,
                    help="write RESULTS.md, report/index.html and README-results.md into DIR "
                         "instead of the repository (for test runs)")
    ap.add_argument("--benchmarks-dir", type=Path, default=ROOT / "benchmarks")
    a = ap.parse_args(argv)

    path = a.results
    if path is None:
        cands = sorted((ROOT / "results").glob("*.json"), key=lambda p: p.stat().st_mtime)
        if not cands:
            sys.exit("no results/*.json; run `runner/run.py measure` first")
        path = cands[-1]
    data = load(path)
    enrich(data, a.benchmarks_dir)
    benches = group(data)
    notes = {}
    for b in benches:
        p = a.benchmarks_dir / b / "NOTES.md"
        if p.is_file():
            notes[b] = p.read_text()
    summ = summary(benches, data.get("versions", {}))
    if a.out_dir:
        # A test run: everything goes under DIR, and the README keeps its real results section.
        a.out_dir.mkdir(parents=True, exist_ok=True)
        a.md = a.out_dir / "RESULTS.md"
        a.html = a.out_dir / "report" / "index.html"
        a.readme = a.out_dir / "README-results.md"
        a.readme.write_text("<!-- results:start -->\n<!-- results:end -->\n")
    write_md(data, benches, summ, notes, a.md)
    write_html(data, benches, summ, notes, a.html)
    print(f"wrote {a.md} and {a.html} from {path}")
    if not a.no_readme and update_readme(a.readme, summ, data):
        print(f"updated the results section of {a.readme}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
