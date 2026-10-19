#!/usr/bin/env python3
"""Lines of code of one implementation directory.

A line counts when it is not blank and is not only a comment. The comment prefix and the source
extensions come from the language's langs/<lang>.toml (`comment`, `extensions`); an impl.toml may
override them and add `loc_exclude = ["file", ...]`. Build outputs, lockfiles and build manifests
are never counted, even when they share an extension with the sources (build.zig, Package.swift,
mix.exs, project.clj ...).

Inline tests and docstrings are not counted either (CONVENTIONS.md, Measurement), chosen by the
file's extension: top-level Cheby `test` blocks (.cheby), top-level Zig `test` blocks (.zig), Rust
`#[cfg(test)]` items (.rs), Python module, class and function docstrings (.py) and Elixir `@doc`
and `@moduledoc` attributes, heredocs included (.ex, .exs).

Usage: loc.py <impl-dir> [--lang <id>]     (prints the count)
       loc.py --selftest
"""

from __future__ import annotations

import argparse
import ast
import bisect
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Directories that hold build outputs, fetched dependencies or editor state.
SKIP_DIRS = {
    ".git", "target", "build", "_build", "out", "dist", "bin", "obj", "deps", "node_modules",
    "zig-out", "zig-cache", ".zig-cache", ".gradle", ".scala-build", ".bsp", ".metals", ".bloop",
    ".cpcache", ".lsp", ".clj-kondo", "nimcache", ".koka", ".build", ".swiftpm", "_opam",
    "__pycache__", ".venv", ".mypy_cache", ".elixir_ls", ".idea", ".vscode",
}

# Manifests, lockfiles and build scripts: configuration, not program code.
SKIP_FILES = {
    "Cargo.toml", "Cargo.lock", "go.mod", "go.sum", "package.json", "package-lock.json",
    "tsconfig.json", "gleam.toml", "manifest.toml", "mix.exs", "mix.lock", "cheby.toml",
    "cheby.lock", "impl.toml", "deps.edn", "project.clj", "build.sbt", "build.sc",
    "project.scala", "dune", "dune-project", "Package.swift", "Package.resolved",
    "build.zig", "build.zig.zon", "CMakeLists.txt", "Makefile", "rebar.config", "rebar.lock",
    "Gemfile", "Gemfile.lock", "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle",
    "NOTES.md", "README.md", "gen.py",
}
SKIP_SUFFIXES = (".lock", ".csproj", ".sln", ".fsproj", ".nimble", ".opam", ".app.src")


def load_lang(lang: str) -> dict:
    with open(ROOT / "langs" / f"{lang}.toml", "rb") as f:
        return tomllib.load(f)


def comment_prefixes(comment) -> tuple[str, ...]:
    if comment is None or comment == "":
        return ()
    if isinstance(comment, str):
        return (comment,)
    return tuple(c for c in comment if c)


def source_files(impl_dir: Path, extensions, exclude=()) -> list[Path]:
    exts = tuple(extensions)
    excluded = set(exclude)
    out = []

    def walk(d: Path):
        for p in sorted(d.iterdir()):
            if p.is_dir():
                if p.name in SKIP_DIRS or p.name.startswith("."):
                    continue
                walk(p)
            elif p.is_file():
                rel = p.relative_to(impl_dir).as_posix()
                if p.name in SKIP_FILES or rel in excluded or p.name in excluded:
                    continue
                if p.name.endswith(SKIP_SUFFIXES):
                    continue
                if exts and not p.name.endswith(exts):
                    continue
                out.append(p)

    if impl_dir.is_dir():
        walk(impl_dir)
    return out


# ---------------------------------------------------------------------------------------------
# Inline tests and docstrings: each finder returns the 0-based line numbers to leave out.

def _skip_string(text: str, i: int) -> int:
    """`text[i]` is `"`: the index just past the closing quote of an escaped string."""
    n = len(text)
    j = i + 1
    while j < n:
        c = text[j]
        if c == "\\":
            j += 2
            continue
        if c == '"':
            return j + 1
        j += 1
    return n


def _raw_string_end(text: str, i: int) -> int:
    """If a raw string `r"…"`, `r#"…"#` (or Rust `br…`) starts at `i`, the index past it, else -1."""
    if i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_"):
        return -1
    j = i
    if text.startswith("br", j):
        j += 2
    elif text[j] == "r":
        j += 1
    else:
        return -1
    k = j
    while k < len(text) and text[k] == "#":
        k += 1
    if k >= len(text) or text[k] != '"':
        return -1
    close = '"' + "#" * (k - j)
    end = text.find(close, k + 1)
    return len(text) if end < 0 else end + len(close)


def _match_brace(text: str, i: int, lang: str) -> int:
    """Index of the `}` that closes the `{` at `i`, skipping strings and comments, or -1.

    `lang` is "cheby", "rust" or "zig". Handles `"…"` strings with `\\` escapes, `//` comments,
    raw strings (Cheby, Rust), nested `/* */` comments and char literals (Rust), and `\\\\` line
    strings and char literals (Zig).
    """
    n = len(text)
    depth = 0
    while i < n:
        c = text[i]
        if c == "/" and text.startswith("//", i):
            nl = text.find("\n", i)
            i = n if nl < 0 else nl
            continue
        if lang == "rust" and c == "/" and text.startswith("/*", i):
            level, i = 1, i + 2
            while i < n and level:
                if text.startswith("/*", i):
                    level, i = level + 1, i + 2
                elif text.startswith("*/", i):
                    level, i = level - 1, i + 2
                else:
                    i += 1
            continue
        if lang == "zig" and c == "\\" and text.startswith("\\\\", i):
            nl = text.find("\n", i)
            i = n if nl < 0 else nl
            continue
        if lang in ("cheby", "rust") and c in "rb":
            end = _raw_string_end(text, i)
            if end >= 0:
                i = end
                continue
        if c == '"':
            i = _skip_string(text, i)
            continue
        if c == "'" and lang in ("rust", "zig"):
            if i + 1 < n and text[i + 1] == "\\":
                end = text.find("'", i + 3)
                i = n if end < 0 else end + 1
                continue
            if i + 2 < n and text[i + 2] == "'":
                i += 3
                continue
            i += 1  # a Rust lifetime or label
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _line_starts(text: str) -> list[int]:
    starts = [0]
    for m in re.finditer("\n", text):
        starts.append(m.end())
    return starts


def _line_of(starts: list[int], offset: int) -> int:
    return bisect.bisect_right(starts, offset) - 1


def _block_lines(text: str, header: re.Pattern, lang: str) -> set[int]:
    """Lines of every item that starts at a `header` match and ends at its matching brace.

    A header followed by `;` before any `{` (Rust `#[cfg(test)] mod tests;`) ends at the `;`.
    An unmatched brace leaves the item counted.
    """
    starts = _line_starts(text)
    out: set[int] = set()
    pos = 0
    while True:
        m = header.search(text, pos)
        if not m:
            return out
        # The first `{` or `;` after the header that is not inside a string or comment.
        i = m.end()
        open_at = -1
        while i < len(text):
            c = text[i]
            if c == "/" and text.startswith("//", i):
                nl = text.find("\n", i)
                i = len(text) if nl < 0 else nl
                continue
            if c == '"':
                i = _skip_string(text, i)
                continue
            if c in "{;":
                open_at = i
                break
            i += 1
        if open_at < 0:
            return out
        end = open_at if text[open_at] == ";" else _match_brace(text, open_at, lang)
        if end < 0:
            pos = m.end()
            continue
        out.update(range(_line_of(starts, m.start()), _line_of(starts, end) + 1))
        pos = end + 1


_CHEBY_TEST = re.compile(r'^test(?=\s*")', re.M)
_ZIG_TEST = re.compile(r'^test\b', re.M)
_RUST_CFG_TEST = re.compile(r'^[ \t]*#\[cfg\(test\)\]', re.M)


def _python_docstrings(text: str) -> set[int]:
    try:
        tree = ast.parse(text)
    except (SyntaxError, ValueError):
        return set()
    out: set[int] = set()
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        body = getattr(node, "body", None)
        if not body:
            continue
        first = body[0]
        if not (isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant)
                and isinstance(first.value.value, str)):
            continue
        lo, hi = first.lineno - 1, (first.end_lineno or first.lineno) - 1
        # `def f(): """doc"""` keeps its line: it also holds the definition.
        if not isinstance(node, ast.Module) and lo == node.lineno - 1:
            lo += 1
        # Code after the docstring on its last line (`"""doc"""; x = 1`) keeps that line.
        if len(body) > 1 and body[1].lineno - 1 == hi:
            hi -= 1
        out.update(range(lo, hi + 1))
    return out


_ELIXIR_DOC = re.compile(r'^\s*@(?:moduledoc|doc)\b(.*)$')
_ELIXIR_HEREDOC = re.compile(r'(?:~[a-zA-Z])?("""|\'\'\')')


def _elixir_docs(text: str) -> set[int]:
    lines = text.split("\n")
    out: set[int] = set()
    k = 0
    while k < len(lines):
        m = _ELIXIR_DOC.match(lines[k])
        if not m:
            k += 1
            continue
        rest = m.group(1)
        start = k
        h = _ELIXIR_HEREDOC.search(rest)
        if h:
            # A heredoc closes on a line whose content starts with the same triple quote.
            quote = h.group(1)
            k += 1
            while k < len(lines) and not lines[k].lstrip().startswith(quote):
                k += 1
        else:
            q = rest.find('"')
            if q >= 0:
                # A one-quote string may still span lines: find its unescaped closing quote.
                joined = "\n".join([rest] + lines[k + 1:])
                end = _skip_string(joined, q)
                k += joined.count("\n", 0, max(end - 1, 0))
        out.update(range(start, min(k, len(lines) - 1) + 1))
        k += 1
    return out


def excluded_lines(text: str, name: str) -> set[int]:
    """0-based lines of the inline tests and docstrings of a source file called `name`."""
    if name.endswith(".cheby"):
        return _block_lines(text, _CHEBY_TEST, "cheby")
    if name.endswith(".zig"):
        return _block_lines(text, _ZIG_TEST, "zig")
    if name.endswith(".rs"):
        return _block_lines(text, _RUST_CFG_TEST, "rust")
    if name.endswith(".py"):
        return _python_docstrings(text)
    if name.endswith((".ex", ".exs")):
        return _elixir_docs(text)
    return set()


def count_lines(text: str, prefixes: tuple[str, ...], name: str = "") -> int:
    skip = excluded_lines(text, name)
    n = 0
    for k, line in enumerate(text.split("\n")):
        if k in skip:
            continue
        s = line.strip()
        if not s:
            continue
        if prefixes and s.startswith(prefixes):
            continue
        n += 1
    return n


def count(impl_dir: Path, comment, extensions, exclude=()) -> int:
    prefixes = comment_prefixes(comment)
    total = 0
    for p in source_files(Path(impl_dir), extensions, exclude):
        try:
            total += count_lines(p.read_text(encoding="utf-8", errors="replace"), prefixes, p.name)
        except OSError:
            pass
    return total


def count_for(impl_dir: Path, cfg: dict) -> int:
    """Count with an already merged language + impl.toml config."""
    return count(impl_dir, cfg.get("comment", ""), cfg.get("extensions", []),
                 cfg.get("loc_exclude", []))


# (file name, source, comment prefixes, expected count)
_SELFTEST_CASES = [
    ("main.cheby", r"""//! A module.
fn main() -> Unit {
  io::println("a { b")
}

test "braces in strings: { and }" {
  let s = "}"
  let q = "\"}"
  let r = r#"say "}" now"#
  // a } in a comment
  assert s == "\{"
}

test "second" {
  assert True
}
fn after() -> Int {
  1
}
""", ("//",), 6),
    ("main.zig", r"""const std = @import("std");
pub fn main() void {
    const s = "{";
    _ = s;
}
test "closing brace in a string }" {
    const c = '}';
    const m =
        \\ a } line
    ;
    _ = c;
    _ = m;
}
test {
    _ = 1;
}
""", ("//",), 5),
    ("main.rs", r"""fn main() {
    println!("{}", "}");
}

#[cfg(test)]
mod tests {
    use super::*;
    // }
    #[test]
    fn t<'a>() {
        let c = '}';
        let e = '\'';
        let s = r#"}"#;
        /* } /* nested } */ */
        assert_eq!(c, '}');
    }
}

#[cfg(test)]
mod more;
fn after() {}
""", ("//",), 4),
    ("main.py", '''"""Module docstring
over two lines."""
import sys


class A:
    """Class docstring."""

    def f(self):
        """Method docstring."""
        return 1


def g(): """One line: the def line stays."""


def h():
    x = "not a docstring"
    """Not first: a plain expression, counted."""
    return x
''', ("#",), 9),
    ("main.ex", '''defmodule Main do
  @moduledoc """
  Heredoc with "quotes" and {braces}.
  """

  @doc "One line."
  def a, do: 1

  @doc false
  def b, do: 2

  @doc ~S"""
  Sigil heredoc.
  """
  def c, do: 3

  @doc "Two
  lines."
  def d, do: 4
end
''', ("#",), 6),
    ("main.go", """package main

func main() {
}
test "not go" {
}
""", ("//",), 5),
]


def selftest() -> int:
    bad = 0
    for name, src, prefixes, want in _SELFTEST_CASES:
        got = count_lines(src, prefixes, name)
        if got != want:
            bad += 1
        print(f"{'ok' if got == want else 'FAIL':4}  {name:12} expected {want}, got {got}")
    print("selftest passed" if not bad else f"selftest: {bad} failed")
    return 1 if bad else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("impl_dir", type=Path, nargs="?")
    ap.add_argument("--lang", help="language id (default: the directory name)")
    ap.add_argument("-v", "--verbose", action="store_true", help="list the counted files")
    ap.add_argument("--selftest", action="store_true", help="check the test and docstring rules")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if a.impl_dir is None:
        ap.error("impl_dir is required")
    lang = a.lang or a.impl_dir.resolve().name
    cfg = dict(load_lang(lang))
    impl_toml = a.impl_dir / "impl.toml"
    if impl_toml.is_file():
        with open(impl_toml, "rb") as f:
            cfg.update(tomllib.load(f))
    if a.verbose:
        prefixes = comment_prefixes(cfg.get("comment"))
        for p in source_files(a.impl_dir, cfg.get("extensions", []), cfg.get("loc_exclude", [])):
            n = count_lines(p.read_text(encoding="utf-8", errors="replace"), prefixes, p.name)
            print(f"{n:6d}  {p.relative_to(a.impl_dir)}", file=sys.stderr)
    print(count_for(a.impl_dir, cfg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
