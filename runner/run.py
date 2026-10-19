#!/usr/bin/env python3
"""Build, verify and measure the benchmark implementations.

Subcommands:
  list       languages, benchmarks, and which implementations exist
  versions   each language's toolchain version (first line of its `version` command)
  inputs     generate the input files (inputs/gen.py) into inputs/data/
  build      build implementations
  verify     build, run every size, diff stdout with expected/<size>.out, print a matrix
  measure    verify, then time run, start-up, compile, peak RSS, artifact size and LOC

Common options: -l/--lang LANG..., -b/--bench BENCH... (space or comma separated),
--benchmarks-dir DIR (default benchmarks/), --build-root DIR (default build/).
The CHEBY environment variable overrides the cheby binary.
See CONVENTIONS.md, "Measurement", for what is measured and how.
"""

from __future__ import annotations

import argparse
import datetime as dt
import difflib
import hashlib
import json
import math
import os
import platform
import re
import shlex
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import loc as loc_mod  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "inputs" / "data"
DEFAULT_CHEBY = (ROOT.parent / "cheby" / "target" / "release" / "cheby").resolve()

LANG_ORDER = [
    "cheby", "gleam", "rust", "rust-tokio", "go", "zig", "odin", "cpp", "erlang", "python",
    "java", "typescript", "swift", "csharp", "elixir", "scala", "clojure", "clojure-coreasync",
    "koka", "ocaml", "ocaml-eio", "nim", "ruby",
]
BENCH_ORDER = [
    "binary_trees", "nbody", "spectral_norm", "mandelbrot", "fannkuch_redux", "word_freq",
    "json_roundtrip", "lru_cache", "ping_pong", "spawn_many", "prime_sieve", "hello_world",
    "compile_large",
]
SIZE_ORDER = ["zero", "test", "bench"]

RUN_TIMEOUT = 300.0        # a bench-size run over this is a timeout
SLOW_RUN = 5.0             # a run over this gets 3 timed runs instead of 10
VERY_SLOW_RUN = 60.0       # a run over this gets 1 timed run
BUILD_TIMEOUT = 1800.0
DEFAULT_GEN = "python3 gen.py {out} {args}"   # compile_large generator command


# ----------------------------------------------------------------------------------------------
# Configuration


def load_toml(path: Path) -> dict:
    with open(path, "rb") as f:
        return tomllib.load(f)


def order_key(order: list[str]):
    def key(x: str):
        return (order.index(x), x) if x in order else (len(order), x)
    return key


class Ctx:
    def __init__(self, benchmarks_dir: Path, build_root: Path, verbose: bool = False):
        self.benchmarks_dir = benchmarks_dir.resolve()
        self.build_root = build_root.resolve()
        self.verbose = verbose
        self.cheby = Path(os.environ.get("CHEBY") or DEFAULT_CHEBY)
        self.langs: dict[str, dict] = {}
        for p in sorted((ROOT / "langs").glob("*.toml")):
            cfg = load_toml(p)
            cfg.setdefault("id", p.stem)
            self.langs[cfg["id"]] = cfg

    def lang_ids(self) -> list[str]:
        return sorted(self.langs, key=order_key(LANG_ORDER))

    def bench_ids(self) -> list[str]:
        if not self.benchmarks_dir.is_dir():
            return []
        out = [
            d.name for d in self.benchmarks_dir.iterdir()
            if d.is_dir() and not d.name.startswith((".", "_"))
            and ((d / "sizes.toml").is_file() or (d / "SPEC.md").is_file()
                 or any((d / lang).is_dir() for lang in self.langs))
        ]
        return sorted(out, key=order_key(BENCH_ORDER))

    def sizes(self, bench: str) -> dict[str, list[str]]:
        p = self.benchmarks_dir / bench / "sizes.toml"
        if not p.is_file():
            return {}
        raw = load_toml(p)
        sizes = {k: [str(a) for a in v] for k, v in raw.items() if isinstance(v, list)}
        return sizes

    def bench_meta(self, bench: str) -> dict:
        p = self.benchmarks_dir / bench / "sizes.toml"
        if not p.is_file():
            return {}
        return {k: v for k, v in load_toml(p).items() if not isinstance(v, list)}

    def impl(self, lang: str, bench: str) -> "Impl | None":
        d = self.benchmarks_dir / bench / lang
        if lang not in self.langs or not d.is_dir():
            return None
        return Impl(self, lang, bench, d)


def is_project_bench(bench: str) -> bool:
    """compile_large-style benchmarks: gen.py writes a project, the runner builds that."""
    return bench == "compile_large" or bench.endswith("compile_large")


class Impl:
    def __init__(self, ctx: Ctx, lang: str, bench: str, path: Path):
        self.ctx, self.lang, self.bench, self.dir = ctx, lang, bench, path
        cfg = dict(ctx.langs[lang])
        impl_toml = path / "impl.toml"
        self.impl_cfg = load_toml(impl_toml) if impl_toml.is_file() else {}
        for k, v in self.impl_cfg.items():
            if k == "env" and isinstance(v, dict):
                cfg["env"] = {**cfg.get("env", {}), **v}
            else:
                cfg[k] = v
        self.cfg = cfg
        self.build_dir = ctx.build_root / lang / bench

    @property
    def name(self) -> str:
        return f"{self.lang}/{self.bench}"

    def has_build(self) -> bool:
        return bool(str(self.cfg.get("build", "")).strip())

    def subst(self, s: str, args: list[str] | None = None, build: Path | None = None) -> str:
        build = build or self.build_dir
        argstr = " ".join(shlex.quote(a.replace("{data}", str(DATA_DIR))) for a in (args or []))
        return (s.replace("{build}", str(build))
                 .replace("{args}", argstr)
                 .replace("{cheby}", shlex.quote(str(self.ctx.cheby)))
                 .replace("{root}", str(ROOT))
                 .replace("{data}", str(DATA_DIR)))

    def env(self) -> dict[str, str]:
        env = dict(os.environ)
        for k, v in (self.cfg.get("env") or {}).items():
            v = self.subst(str(v))
            # $VAR and ${VAR} expand against the current environment (PATH prefixes).
            v = re.sub(r"\$\{(\w+)\}|\$(\w+)", lambda m: env.get(m.group(1) or m.group(2), ""), v)
            env[k] = v
        return env


# ----------------------------------------------------------------------------------------------
# Processes


class Proc:
    def __init__(self, rc, out: bytes, err: bytes, secs: float, timed_out: bool):
        self.rc, self.out, self.err, self.secs, self.timed_out = rc, out, err, secs, timed_out

    @property
    def ok(self) -> bool:
        return not self.timed_out and self.rc == 0


def sh(cmd: str, cwd: Path, env: dict, timeout: float | None, stdout=subprocess.PIPE) -> Proc:
    """Run `cmd` through sh -c in its own process group, killing the group on timeout."""
    t0 = time.monotonic()
    p = subprocess.Popen(["sh", "-c", cmd], cwd=cwd, env=env, stdout=stdout,
                         stderr=subprocess.PIPE, stdin=subprocess.DEVNULL, start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout)
        timed_out = False
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = p.communicate()
        timed_out = True
    return Proc(p.returncode, out or b"", err or b"", time.monotonic() - t0, timed_out)


def first_line(b: bytes | str) -> str:
    s = b.decode(errors="replace") if isinstance(b, bytes) else b
    for line in s.splitlines():
        if line.strip():
            return line.strip()
    return ""


def tail(b: bytes, n: int = 15) -> str:
    lines = b.decode(errors="replace").rstrip().splitlines()
    return "\n".join(lines[-n:])


def log(msg: str):
    print(msg, file=sys.stderr, flush=True)


# ----------------------------------------------------------------------------------------------
# Build and run


def do_build(impl: Impl, cwd: Path | None = None, build: Path | None = None) -> tuple[bool, str]:
    """Build once (untimed). Returns (ok, log tail)."""
    build = build or impl.build_dir
    build.mkdir(parents=True, exist_ok=True)
    if not impl.has_build():
        return True, ""
    cmd = impl.subst(impl.cfg["build"], build=build)
    p = sh(cmd, cwd or impl.dir, impl.env(), BUILD_TIMEOUT)
    text = (p.out + p.err)
    (build / "build.log").write_bytes(f"$ {cmd}\n".encode() + text)
    if p.timed_out:
        return False, f"build timed out after {BUILD_TIMEOUT:.0f}s"
    return p.rc == 0, tail(text)


def run_cmd(impl: Impl, args: list[str], build: Path | None = None) -> str:
    return impl.subst(impl.cfg["run"], args=args, build=build)


def check_output(impl: Impl, size: str, args: list[str], timeout: float) -> dict:
    """Run one size and compare stdout with expected/<size>.out."""
    p = sh(run_cmd(impl, args), impl.dir, impl.env(), timeout)
    res = {"size": size, "secs": p.secs, "out": p.out, "err": p.err}
    exp_path = impl.ctx.benchmarks_dir / impl.bench / "expected" / f"{size}.out"
    if p.timed_out:
        res["status"] = "timeout"
    elif p.rc != 0:
        res["status"] = "FAIL"
        res["why"] = f"exit code {p.rc}"
    elif not exp_path.is_file():
        res["status"] = "no-exp"
    elif exp_path.read_bytes() != p.out:
        res["status"] = "FAIL"
        res["why"] = "wrong output"
        res["expected"] = exp_path.read_bytes()
    else:
        res["status"] = "ok"
    return res


def show_diff(expected: bytes, got: bytes, n: int = 12) -> str:
    a = expected.decode(errors="replace").splitlines(keepends=True)
    b = got.decode(errors="replace").splitlines(keepends=True)
    d = list(difflib.unified_diff(a, b, "expected", "got", n=1))
    if not d:
        return "    (outputs differ only in line endings or the final newline)"
    return "".join("    " + line if line.endswith("\n") else "    " + line + "\n" for line in d[: n + 3])


# ----------------------------------------------------------------------------------------------
# Project benchmarks (compile_large)


def gen_project(impl: Impl, size: str, args: list[str]) -> tuple[Path, Path, str | None]:
    """Generate the project for one size. Returns (project dir, its {build} dir, error)."""
    project = impl.build_dir / f"project-{size}"
    build = impl.build_dir / f"out-{size}"
    gen_tmpl = impl.cfg.get("gen") or impl.ctx.bench_meta(impl.bench).get("gen") or DEFAULT_GEN
    gen_py = impl.dir / "gen.py"
    marker = project / ".cheby-compare-gen"
    stamp = hashlib.sha256(
        (gen_tmpl + "\0" + "\0".join(args) + "\0").encode()
        + (gen_py.read_bytes() if gen_py.is_file() else b"")
    ).hexdigest()
    if marker.is_file() and marker.read_text() == stamp:
        return project, build, None
    if project.exists():
        shutil.rmtree(project)
    project.parent.mkdir(parents=True, exist_ok=True)
    argstr = " ".join(shlex.quote(a) for a in args)
    cmd = gen_tmpl.replace("{out}", shlex.quote(str(project))).replace("{args}", argstr)
    p = sh(cmd, impl.dir, impl.env(), 600)
    if not p.ok:
        return project, build, f"gen.py failed: {tail(p.out + p.err)}"
    project.mkdir(parents=True, exist_ok=True)
    marker.write_text(stamp)
    if build.exists():
        shutil.rmtree(build)
    return project, build, None


def check_project(impl: Impl, size: str, project: Path, build: Path, timeout: float) -> dict:
    ok, text = do_build(impl, cwd=project, build=build)
    if not ok:
        return {"status": "build-error", "why": text}
    p = sh(impl.subst(impl.cfg["run"], args=[], build=build), project, impl.env(), timeout)
    exp_path = impl.ctx.benchmarks_dir / impl.bench / "expected" / f"{size}.out"
    res = {"secs": p.secs, "out": p.out, "err": p.err}
    if p.timed_out:
        res["status"] = "timeout"
    elif p.rc != 0:
        res.update(status="FAIL", why=f"exit code {p.rc}: {tail(p.err, 5)}")
    elif exp_path.is_file() and exp_path.read_bytes() != p.out:
        res.update(status="FAIL", why="wrong output", expected=exp_path.read_bytes())
    else:
        res["status"] = "ok"
    return res


# ----------------------------------------------------------------------------------------------
# Selection


def split_list(values: list[str] | None) -> list[str] | None:
    if not values:
        return None
    out = []
    for v in values:
        out.extend(x for x in v.split(",") if x)
    return out


def select(ctx: Ctx, a) -> tuple[list[str], list[str]]:
    langs = split_list(a.lang) or ctx.lang_ids()
    benches = split_list(a.bench) or ctx.bench_ids()
    for lang in langs:
        if lang not in ctx.langs:
            sys.exit(f"unknown language {lang!r}; known: {', '.join(ctx.lang_ids())}")
    for b in benches:
        if not (ctx.benchmarks_dir / b).is_dir():
            sys.exit(f"unknown benchmark {b!r}; known: {', '.join(ctx.bench_ids())}")
    return langs, benches


def print_matrix(langs: list[str], benches: list[str], cell) -> None:
    w0 = max([len("lang")] + [len(x) for x in langs])
    widths = [max(len(b), max((len(cell(lang, b)) for lang in langs), default=0)) for b in benches]
    print("  ".join(["lang".ljust(w0)] + [b.ljust(w) for b, w in zip(benches, widths)]))
    print("  ".join(["-" * w0] + ["-" * w for w in widths]))
    for lang in langs:
        print("  ".join([lang.ljust(w0)] + [cell(lang, b).ljust(w) for b, w in zip(benches, widths)]).rstrip())


# ----------------------------------------------------------------------------------------------
# Subcommands: list, versions, inputs, build, verify


def cmd_list(ctx: Ctx, a) -> int:
    print(f"benchmarks dir: {ctx.benchmarks_dir}")
    print(f"cheby binary:   {ctx.cheby}{'' if ctx.cheby.exists() else '  (MISSING)'}\n")
    print("Languages:")
    for lid in ctx.lang_ids():
        c = ctx.langs[lid]
        print(f"  {lid:<18} {c.get('name', lid):<12} {c.get('kind', '?')}")
    langs, benches = select(ctx, a)
    print("\nBenchmarks:")
    for b in benches:
        sizes = ctx.sizes(b)
        exp = sorted(p.stem for p in (ctx.benchmarks_dir / b / "expected").glob("*.out"))
        print(f"  {b:<18} sizes: {', '.join(f'{k}={v}' for k, v in sizes.items()) or '-'}"
              f"; expected: {', '.join(exp) or '-'}")
    print("\nImplementations (x = present):")
    print_matrix(langs, benches, lambda lang, b: "x" if ctx.impl(lang, b) else ".")
    return 0


def lang_version(ctx: Ctx, lid: str) -> str:
    cfg = ctx.langs[lid]
    cmd = cfg.get("version")
    if not cmd:
        return ""
    fake = Impl.__new__(Impl)
    fake.ctx, fake.cfg, fake.build_dir = ctx, cfg, ctx.build_root / lid
    try:
        p = sh(fake.subst(cmd), ROOT, fake.env(), 60)
    except OSError as e:
        return f"error: {e}"
    if p.timed_out:
        return "error: timed out"
    line = first_line(p.out) or first_line(p.err)
    return line if p.rc == 0 else f"error ({p.rc}): {line}"


def cmd_versions(ctx: Ctx, a) -> int:
    langs = split_list(a.lang) or ctx.lang_ids()
    out = {}
    for lid in langs:
        out[lid] = lang_version(ctx, lid)
        print(f"{lid:<18} {out[lid]}", flush=True)
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=2) + "\n")
    return 0


def cmd_inputs(ctx: Ctx, a) -> int:
    argv = [sys.executable, str(ROOT / "inputs" / "gen.py")] + (["--force"] if a.force else [])
    return subprocess.call(argv, cwd=ROOT)


def cmd_build(ctx: Ctx, a) -> int:
    langs, benches = select(ctx, a)
    failed = 0
    for b in benches:
        for lang in langs:
            impl = ctx.impl(lang, b)
            if not impl:
                continue
            if is_project_bench(b):
                sizes = ctx.sizes(b)
                size = "test" if "test" in sizes else next(iter(sizes), None)
                if size is None:
                    log(f"{impl.name}: no sizes in sizes.toml")
                    continue
                project, build, err = gen_project(impl, size, sizes[size])
                ok, text = (False, err) if err else do_build(impl, cwd=project, build=build)
            else:
                t0 = time.monotonic()
                ok, text = do_build(impl)
            if not impl.has_build() and ok:
                print(f"{impl.name:<32} no build step")
            elif ok:
                print(f"{impl.name:<32} built")
            else:
                failed += 1
                print(f"{impl.name:<32} BUILD ERROR\n{indent(text)}")
    return 1 if failed else 0


def indent(s: str, n: int = 4) -> str:
    return "\n".join(" " * n + line for line in (s or "").splitlines())


def cmd_verify(ctx: Ctx, a) -> int:
    langs, benches = select(ctx, a)
    sizes_wanted = split_list([a.sizes]) or ["zero", "test"]
    cells: dict[tuple[str, str], str] = {}
    problems = []
    for b in benches:
        sizes = ctx.sizes(b)
        for lang in langs:
            impl = ctx.impl(lang, b)
            if not impl:
                cells[(lang, b)] = "missing"
                continue
            if is_project_bench(b):
                cells[(lang, b)] = verify_project(impl, sizes, sizes_wanted, problems, a)
                continue
            ok, text = do_build(impl)
            if not ok:
                cells[(lang, b)] = "build-error"
                problems.append(f"{impl.name}: build error\n{indent(text)}")
                log(f"{impl.name}: build-error")
                continue
            results = []
            for size in [s for s in SIZE_ORDER + sorted(sizes) if s in sizes_wanted and s in sizes]:
                if size in [r["size"] for r in results]:
                    continue
                r = check_output(impl, size, sizes[size], a.timeout)
                results.append(r)
                if r["status"] != "ok":
                    msg = f"{impl.name} [{size}]: {r['status']} {r.get('why', '')}".rstrip()
                    if r["status"] == "FAIL" and r.get("err"):
                        msg += "\n" + indent(tail(r["err"], 8))
                    if a.diff and "expected" in r:
                        msg += "\n" + show_diff(r["expected"], r["out"])
                    problems.append(msg)
            statuses = [r["status"] for r in results]
            if not results:
                cell = "no-sizes"
            elif "FAIL" in statuses:
                cell = "FAIL"
            elif "timeout" in statuses:
                cell = "timeout"
            elif "no-exp" in statuses:
                cell = "no-exp" if statuses.count("ok") == 0 else "ok*"
            else:
                cell = "ok"
            cells[(lang, b)] = cell
            log(f"{impl.name}: {cell} ({', '.join(f'{r['size']} {r['secs']:.2f}s' for r in results)})")
    print()
    print_matrix(langs, benches, lambda lang, b: cells.get((lang, b), "missing"))
    if any(v == "ok*" for v in cells.values()):
        print("\nok* = the sizes with an expected output match; some sizes have no expected/<size>.out")
    if problems:
        print("\nProblems:")
        for p in problems:
            print("  " + p)
    bad = any(v in ("FAIL", "build-error", "timeout") for v in cells.values())
    return 1 if bad else 0


def verify_project(impl: Impl, sizes: dict, sizes_wanted, problems, a) -> str:
    if not sizes:
        problems.append(f"{impl.name}: no sizes in sizes.toml")
        return "no-sizes"
    chosen = [s for s in sizes if s in sizes_wanted] or [next(iter(sizes))]
    cell = "ok"
    for size in chosen:
        project, build, err = gen_project(impl, size, sizes[size])
        if err:
            problems.append(f"{impl.name} [{size}]: {err}")
            return "build-error"
        r = check_project(impl, size, project, build, a.timeout)
        log(f"{impl.name} [{size}]: {r['status']}")
        if r["status"] != "ok":
            problems.append(f"{impl.name} [{size}]: {r['status']} {r.get('why', '')}")
            cell = r["status"]
            if a.diff and "expected" in r:
                problems.append(show_diff(r["expected"], r["out"]))
    return cell


# ----------------------------------------------------------------------------------------------
# Measurement helpers


def hyperfine(cmd: str, cwd: Path, env: dict, runs: int, warmup: int,
              prepare: str | None = None, per_run_timeout: float = RUN_TIMEOUT) -> dict:
    """Time `cmd` with hyperfine. Returns stats in seconds, or {"error": ...}."""
    fd, tmp = tempfile.mkstemp(prefix="hf-", suffix=".json")
    os.close(fd)
    argv = ["hyperfine", "--export-json", tmp, "--runs", str(runs), "--warmup", str(warmup),
            "--style", "basic", "--shell=default"]
    # hyperfine 2 runs commands without a shell by default, but the langs/*.toml commands use
    # shell syntax (&&, globs, VAR=...), as `verify` (sh -c) does. hyperfine subtracts the
    # shell's own spawn time, so this costs the measured programs nothing.
    if prepare:
        argv += ["--prepare", prepare]
    argv.append(cmd)
    total = (runs + warmup) * per_run_timeout + 60
    try:
        p = subprocess.run(argv, cwd=cwd, env=env, capture_output=True, timeout=total,
                           start_new_session=True)
    except subprocess.TimeoutExpired:
        os.unlink(tmp)
        return {"error": "timeout"}
    try:
        if p.returncode != 0:
            return {"error": tail(p.stderr or p.stdout, 6)}
        data = json.loads(Path(tmp).read_text())["results"][0]
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return parse_hyperfine_result(data, runs, warmup)


def parse_hyperfine_result(data: dict, runs: int, warmup: int) -> dict:
    """One entry of hyperfine's results[], in the schema of hyperfine 1.x or 2.x."""
    if "summary" in data:  # hyperfine 2: schema_version 2
        summ = data["summary"]
        wall = summ["time_wall_clock"]
        times = [m["time_wall_clock"]["value"] for m in data.get("measurements", [])]
        rss = summ.get("memory_peak_resident", {})
        return {
            "median": wall["median"], "mean": wall["mean"], "stddev": wall.get("stddev"),
            "min": wall["min"], "max": wall["max"],
            "user": summ.get("time_user", {}).get("mean"),
            "system": summ.get("time_system", {}).get("mean"),
            "runs": len(times) or runs, "warmup": warmup, "times": times,
            "hyperfine_peak_rss_max": rss.get("max"),
        }
    times = data.get("times") or []
    return {
        "median": data["median"], "mean": data["mean"], "stddev": data.get("stddev"),
        "min": data["min"], "max": data["max"], "user": data.get("user"),
        "system": data.get("system"), "runs": len(times) or runs, "warmup": warmup,
        "times": times,
    }


def peak_rss(cmd: str, cwd: Path, env: dict, timeout: float) -> int | None:
    """Maximum resident set size in bytes from /usr/bin/time -l (macOS) or -v (GNU)."""
    if sys.platform == "darwin":
        argv = ["/usr/bin/time", "-l", "sh", "-c", cmd]
    else:
        argv = ["/usr/bin/time", "-v", "sh", "-c", cmd]
    try:
        p = subprocess.run(argv, cwd=cwd, env=env, stdout=subprocess.DEVNULL,
                           stderr=subprocess.PIPE, timeout=timeout, start_new_session=True)
    except (subprocess.TimeoutExpired, OSError):
        return None
    text = p.stderr.decode(errors="replace")
    m = re.findall(r"^\s*(\d+)\s+maximum resident set size", text, re.M)
    if m:
        return int(m[-1])
    m = re.findall(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    if m:
        return int(m[-1]) * 1024
    return None


def path_size(p: Path) -> int | None:
    if p.is_file():
        return p.stat().st_size
    if p.is_dir():
        return sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
    return None


def machine_info() -> dict:
    def q(argv):
        try:
            return subprocess.run(argv, capture_output=True, text=True, timeout=10).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            return ""
    info = {"platform": platform.platform(), "arch": platform.machine(),
            "python": platform.python_version(), "hyperfine": q(["hyperfine", "--version"])}
    if sys.platform == "darwin":
        info.update(
            cpu=q(["sysctl", "-n", "machdep.cpu.brand_string"]),
            cores=int(q(["sysctl", "-n", "hw.ncpu"]) or 0),
            perf_cores=int(q(["sysctl", "-n", "hw.perflevel0.physicalcpu"]) or 0),
            efficiency_cores=int(q(["sysctl", "-n", "hw.perflevel1.physicalcpu"]) or 0),
            memory_bytes=int(q(["sysctl", "-n", "hw.memsize"]) or 0),
            os=f"macOS {q(['sw_vers', '-productVersion'])} ({q(['sw_vers', '-buildVersion'])})",
        )
    else:
        info.update(cpu=platform.processor(), cores=os.cpu_count(), os=platform.platform())
    return info


def cheby_commit(ctx: Ctx) -> str:
    repo = ctx.cheby.parent.parent.parent
    try:
        p = subprocess.run(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True, timeout=10)
        return p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


class Results:
    def __init__(self, path: Path, quick: bool):
        self.path = path
        if path.is_file():
            self.data = json.loads(path.read_text())
            log(f"resuming {path} ({len(self.data.get('entries', {}))} entries)")
        else:
            self.data = {"schema": 1, "created": now(), "quick": quick, "entries": {},
                         "versions": {}}
        self.data.setdefault("entries", {})
        self.data.setdefault("versions", {})
        if self.data.get("quick") != quick:
            log(f"warning: {path} was made with quick={self.data.get('quick')}, now quick={quick}")

    def save(self):
        self.data["updated"] = now()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(self.data, indent=1) + "\n")
        tmp.replace(self.path)


def now() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def brief(st: dict | None) -> str:
    if not st:
        return "-"
    if "error" in st:
        return f"error: {st['error'].splitlines()[0] if st['error'] else ''}"
    n = f" n={st['runs']}" if 'runs' in st else ''
    return f"{fmt_s(st['median'])} [{fmt_s(st['min'])}-{fmt_s(st['max'])}]{n}"


def fmt_s(s: float) -> str:
    if s is None:
        return "-"
    if s < 1:
        return f"{s * 1000:.1f}ms"
    return f"{s:.2f}s"


# ----------------------------------------------------------------------------------------------
# measure


def cmd_measure(ctx: Ctx, a) -> int:
    langs, benches = select(ctx, a)
    day = dt.date.today().isoformat()
    out = Path(a.out) if a.out else ROOT / "results" / (f"quick-{day}.json" if a.quick else f"{day}.json")
    res = Results(out, a.quick)
    d = res.data
    d["machine"] = machine_info()
    d["cheby"] = {"binary": str(ctx.cheby), "commit": cheby_commit(ctx)}
    d["method"] = {
        "runs": 3 if a.quick else 10, "warmup": 0 if a.quick else 1,
        "slow_runs": 3, "slow_threshold_s": SLOW_RUN, "very_slow_runs": 1, "very_slow_threshold_s": VERY_SLOW_RUN, "timeout_s": a.timeout,
        "compile_runs": 3 if a.quick else 5,
    }
    if not shutil.which("hyperfine"):
        sys.exit("hyperfine is not on PATH (see setup.sh)")
    for lang in langs:
        if lang not in d["versions"] and any(ctx.impl(lang, b) for b in benches):
            d["versions"][lang] = lang_version(ctx, lang)
    res.save()

    try:
        for b in benches:
            for lang in langs:
                impl = ctx.impl(lang, b)
                if not impl:
                    continue
                key = impl.name
                old = d["entries"].get(key)
                if is_project_bench(b):
                    measure_project(impl, res, a)
                    continue
                if old and not a.redo and not (a.retry_failed and old.get("status") != "ok"):
                    log(f"{key}: already measured ({old.get('status')}), skipping")
                    continue
                log(f"== {key}")
                entry = measure_one(impl, a)
                d["entries"][key] = entry
                res.save()
                comp = (f"compile ≈ {brief(entry['compile_estimate'])} (estimate)"
                        if entry.get("compile_estimate") else f"compile {brief(entry.get('compile'))}")
                log(f"   {entry['status']}: run {brief(entry.get('run'))}; start-up "
                    f"{brief(entry.get('startup'))}; {comp}")
    except KeyboardInterrupt:
        res.save()
        log(f"interrupted; partial results kept in {out}")
        return 130
    res.save()
    log(f"results written to {out}")
    return 0


def base_entry(impl: Impl) -> dict:
    e = {
        "lang": impl.lang, "bench": impl.bench, "kind": impl.cfg.get("kind", ""),
        "name": impl.cfg.get("name", impl.lang), "libs": impl.cfg.get("libs", []),
        "notes": impl.cfg.get("notes", ""), "measured_at": now(),
        "loc": loc_mod.count_for(impl.dir, impl.cfg),
    }
    # impl.toml keys the report honours: rows measured but left out of comparisons, and the
    # expected reason for a failure.
    for k in ("comparable", "comparable_note", "known_failure"):
        if k in impl.cfg:
            e[k] = impl.cfg[k]
    return e


def measure_one(impl: Impl, a) -> dict:
    e = base_entry(impl)
    sizes = impl.ctx.sizes(impl.bench)
    env = impl.env()
    runs, warmup = (3, 0) if a.quick else (10, 1)

    ok, text = do_build(impl)
    if not ok:
        e.update(status="build-error", error=text)
        return e

    # Output is checked before anything is timed. The bench-size check doubles as the probe
    # that picks the number of runs.
    probe = {}
    for size in ("zero", "bench"):
        if size not in sizes:
            continue
        r = check_output(impl, size, sizes[size], a.timeout)
        probe[size] = r
        if r["status"] == "timeout":
            e.update(status="timeout", timeout_size=size, error=f"over {a.timeout:g} s at size {size}")
            break
        if r["status"] != "ok":
            st = "unverified" if r["status"] == "no-exp" else "wrong-output"
            e.update(status=st, error=f"size {size}: {r.get('why', 'no expected/' + size + '.out')}")
            if r.get("err"):
                e["stderr"] = tail(r["err"], 10)
            return e
    if not probe:
        e.update(status="unverified", error="sizes.toml has neither zero nor bench")
        return e

    if "bench" in probe and probe["bench"]["status"] == "ok":
        secs = probe["bench"]["secs"]
        if secs > VERY_SLOW_RUN:
            n, w = 1, 0
        elif secs > SLOW_RUN:
            n, w = 3, 0
        else:
            n, w = runs, warmup
        e["run"] = hyperfine(run_cmd(impl, sizes["bench"]), impl.dir, env, n, w,
                             per_run_timeout=a.timeout)
        e["args"] = sizes["bench"]
    if "zero" in probe and probe["zero"]["status"] == "ok":
        e["startup"] = hyperfine(run_cmd(impl, sizes["zero"]), impl.dir, env, runs, warmup)
    if impl.has_build():
        clean = str(impl.cfg.get("clean", "")).strip()
        if not clean:
            log(f"   warning: {impl.name} has a build but no clean; compile time is incremental")
        e["compile"] = hyperfine(impl.subst(impl.cfg["build"]), impl.dir, env,
                                 3 if a.quick else 5, 0,
                                 prepare=impl.subst(clean) if clean else None,
                                 per_run_timeout=BUILD_TIMEOUT)
        e["compile"]["prepared_with_clean"] = bool(clean)
        warm = warm_compile(impl, impl.dir, env, 3 if a.quick else 5, a.quick)
        if warm is not None:
            e["compile_warm"] = warm
        # The last timed build leaves the artifact in place, but make sure it is there.
        do_build(impl)
    if impl.cfg.get("check"):
        e["check"] = hyperfine(impl.subst(impl.cfg["check"]), impl.dir, env,
                               3 if a.quick else 5, 0 if a.quick else 1)
    if impl.cfg.get("kind") == "jit":
        add_jit_estimates(e)
    if "bench" in sizes and e.get("status") != "timeout":
        e["rss_bytes"] = peak_rss(run_cmd(impl, sizes["bench"]), impl.dir, env, a.timeout + 30)
    elif "bench" not in sizes and "zero" in sizes:
        e["rss_bytes"] = peak_rss(run_cmd(impl, sizes["zero"]), impl.dir, env, a.timeout + 30)
    if impl.cfg.get("artifact"):
        e["artifact_bytes"] = path_size(Path(impl.subst(impl.cfg["artifact"])))
    if "status" not in e:
        errs = [k for k in ("run", "startup", "compile") if isinstance(e.get(k), dict) and "error" in e[k]]
        e["status"] = "run-error" if errs else "ok"
        if errs:
            e["error"] = "; ".join(f"{k}: {e[k]['error']}" for k in errs)
    return e



def warm_compile(impl: "Impl", cwd: Path, env: dict, n: int, quick: bool, build: Path | None = None) -> dict | None:
    """Compile time with the language's build server running and warmed up (Scala's Bloop,
    .NET's build server). Only for configs that set `warm_start` or `build_warm`; the cold
    `build` stays the main number (CONVENTIONS.md, "Measurement")."""
    cfg = impl.cfg
    if not (cfg.get("warm_start") or cfg.get("build_warm")):
        return None
    kw = {"build": build} if build is not None else {}
    clean = str(cfg.get("clean", "")).strip()
    if cfg.get("warm_start"):
        sh(impl.subst(cfg["warm_start"], **kw), cwd, env, BUILD_TIMEOUT)
    try:
        r = hyperfine(impl.subst(cfg.get("build_warm") or cfg["build"], **kw), cwd, env,
                      n, 1 if quick else 3, prepare=impl.subst(clean, **kw) if clean else None,
                      per_run_timeout=BUILD_TIMEOUT)
        r["warm"] = True
        return r
    finally:
        if cfg.get("warm_stop"):
            sh(impl.subst(cfg["warm_stop"], **kw), cwd, env, BUILD_TIMEOUT)


def add_jit_estimates(e: dict) -> None:
    """Cheby until M3: compile = median run at size 0; runtime = bench median - that."""
    st = e.get("startup")
    if not st or "error" in st:
        return
    comp = st["median"]
    e["compile_estimate"] = {"median": comp, "min": st["min"], "max": st["max"],
                             "estimated": True, "method": "median run at size 0"}
    run = e.get("run")
    if run and "error" not in run:
        e["runtime_estimate"] = {
            "median": max(run["median"] - comp, 0.0),
            "min": max(run["min"] - comp, 0.0),
            "max": max(run["max"] - comp, 0.0),
            "estimated": True,
            "method": "median run at bench size minus compile_estimate",
            "clamped": run["median"] - comp < 0,
        }
    e["estimated"] = True


def measure_project(impl: Impl, res: Results, a) -> None:
    d = res.data
    key = impl.name
    sizes = impl.ctx.sizes(impl.bench)
    entry = d["entries"].get(key)
    if entry is None or a.redo:
        entry = base_entry(impl)
        entry.update(status="ok", sizes={}, project=True)
        d["entries"][key] = entry
    env = impl.env()
    n = 3 if a.quick else 5
    for size, args in sizes.items():
        old = entry["sizes"].get(size)
        if old and not (a.retry_failed and old.get("status") != "ok"):
            log(f"{key} [{size}]: already measured, skipping")
            continue
        log(f"== {key} [{size}]")
        s = {"args": args, "measured_at": now()}
        project, build, err = gen_project(impl, size, args)
        if err:
            s.update(status="build-error", error=err)
        else:
            s["files"] = sum(1 for p in loc_mod.source_files(project, impl.cfg.get("extensions", [])))
            s["loc"] = loc_mod.count_for(project, impl.cfg)
            r = check_project(impl, size, project, build, a.timeout)
            if r["status"] != "ok":
                s.update(status=r["status"], error=r.get("why", ""))
            elif impl.has_build():
                clean = str(impl.cfg.get("clean", "")).strip()
                s["measure"] = "build"
                s["compile"] = hyperfine(impl.subst(impl.cfg["build"], build=build), project, env,
                                         n, 0, prepare=impl.subst(clean, build=build) if clean else None,
                                         per_run_timeout=BUILD_TIMEOUT)
                s["compile"]["prepared_with_clean"] = bool(clean)
                warm = warm_compile(impl, project, env, n, a.quick, build=build)
                if warm is not None:
                    s["compile_warm"] = warm
            else:
                # JIT and interpreters: the time to load (and for Cheby, compile) everything.
                s["measure"] = "run"
                s["compile"] = hyperfine(impl.subst(impl.cfg["run"], args=[], build=build),
                                         project, env, n, 0 if a.quick else 1)
                if impl.cfg.get("kind") == "jit":
                    s["compile"]["estimated"] = True
            if impl.cfg.get("check") and "status" not in s:
                s["check"] = hyperfine(impl.subst(impl.cfg["check"], build=build), project, env,
                                       n, 0 if a.quick else 1)
            if "status" not in s:
                s["status"] = "error" if "error" in s.get("compile", {}) else "ok"
        entry["sizes"][size] = s
        statuses = [v.get("status") for v in entry["sizes"].values()]
        entry["status"] = "ok" if all(x == "ok" for x in statuses) else next(x for x in statuses if x != "ok")
        res.save()
        log(f"   {s['status']}: {s.get('measure', '')} {brief(s.get('compile'))}")


# ----------------------------------------------------------------------------------------------


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--benchmarks-dir", type=Path, default=ROOT / "benchmarks",
                    help="where the benchmark directories live (default: benchmarks/)")
    ap.add_argument("--build-root", type=Path, default=None,
                    help="root of the per-implementation build dirs (default: build/)")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def sel(p):
        p.add_argument("-l", "--lang", nargs="+", help="languages (default: all)")
        p.add_argument("-b", "--bench", nargs="+", help="benchmarks (default: all)")

    p = sub.add_parser("list", help="languages, benchmarks and implementations")
    sel(p)
    p = sub.add_parser("versions", help="toolchain versions")
    p.add_argument("-l", "--lang", nargs="+")
    p.add_argument("--json", help="also write them to this JSON file")
    p = sub.add_parser("inputs", help="generate inputs/data/")
    p.add_argument("--force", action="store_true")
    p = sub.add_parser("build", help="build implementations")
    sel(p)
    p = sub.add_parser("verify", help="build, run and diff against expected/")
    sel(p)
    p.add_argument("--sizes", default="zero,test", help="comma-separated sizes (default zero,test)")
    p.add_argument("--diff", action="store_true", help="show the first differing lines")
    p.add_argument("--timeout", type=float, default=RUN_TIMEOUT)
    p = sub.add_parser("measure", help="verify and time")
    sel(p)
    p.add_argument("--out", help="results JSON (default results/<date>.json); resumed if it exists")
    p.add_argument("--quick", action="store_true", help="3 runs, no warm-up (smoke test)")
    p.add_argument("--redo", action="store_true", help="re-measure entries already in --out")
    p.add_argument("--retry-failed", action="store_true", help="re-measure entries whose status is not ok")
    p.add_argument("--timeout", type=float, default=RUN_TIMEOUT)
    a = ap.parse_args(argv)

    build_root = a.build_root or ROOT / "build"
    ctx = Ctx(a.benchmarks_dir, build_root, a.verbose)
    return {
        "list": cmd_list, "versions": cmd_versions, "inputs": cmd_inputs, "build": cmd_build,
        "verify": cmd_verify, "measure": cmd_measure,
    }[a.cmd](ctx, a)


if __name__ == "__main__":
    sys.exit(main())
