"""Writes the Koka project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one directory: main.kk and one module per index, m0000.kk to
m<M-1>.kk. `koka ... main.kk` finds the modules on its search path (the
current directory) and compiles each one, and its generated C, in dependency
order. Koka has no formatter; the output follows the layout of Koka's own
library sources (two-space indentation) and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [f"// Module {i} of a generated compile_large project.\nmodule {name(i)}\n"]
    if i > 0:
        out.append(f"\nimport {name(i - 1)}\n")
    out.append(
        f"""
// The modulus that keeps every value small.
val p = {P}

// A record that `make-item` builds and `item-score` reads.
struct item
  id : int
  size : int
  weight : int

// A sum type that `make-shape` builds and `area` matches.
type shape
  Circle(r : int)
  Rect(w : int, h : int)
  Tri(a : int, b : int, c : int)
  Empty

// The first link of this module's chain, also called by the next module.
pub fun base(x : int) : int
  val a = x * {k[0]} + {k[1]}
  val b = a % p
  (b * {k[2]} + {k[3]}) % p
"""
    )
    for j in range(1, 14):
        # Module i also sees the previous module's `base`, so its own needs its module name.
        prev = f"{name(i)}/base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
// Link {j} of the chain.
fun step{j}(x : int) : int
  val y = {prev}(x)
  val a = y * {k[4 * j]} + x
  val b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % p
  if b % 2 == 0 then (a + b) % p else (a + b * {k[4 * j + 3]}) % p
"""
        )
    out.append(
        f"""
// Builds an item from `x`.
fun make-item(x : int) : item
  Item(id = x % {k[56]}, size = x % 1000 + {k[57]}, weight = x * {k[58]} % p)

// Reads every field of `it`.
fun item-score(it : item) : int
  (it.id * {k[59]} + it.size * {k[60]} + it.weight) % p

// Picks a shape from `x`.
fun make-shape(x : int) : shape
  match x % 4
    0 -> Circle(x % {k[61]} + 1)
    1 -> Rect(x % {k[62]} + 1, x % {k[63]} + 1)
    2 -> Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
    _ -> Empty

// The area of `s`, in whole units.
fun area(s : shape) : int
  match s
    Circle(r) -> 3 * r * r
    Rect(w, h) -> w * h
    Tri(a, b, c) -> a * b / 2 + c
    Empty -> {k[67]}
"""
    )
    if i > 0:
        out.append(
            f"""
// Calls into the previous module.
fun link(x : int) : int
  ({name(i - 1)}/base(x) + {k[68]}) % p
"""
        )
    else:
        out.append(
            f"""
// The first module has no previous module to call.
fun link(x : int) : int
  (x + {k[68]}) % p
"""
        )
    out.append(
        """
// The function `main` calls.
pub fun entry(x : int) : int
  val s = step13(x)
  val r = item-score(make-item(s))
  val h = area(make-shape(x))
  val l = link(x)
  (s + r + h + l) % p
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f"import {name(i)}\n" for i in range(m))
    one_line = f"  val entries = [{', '.join(f'{name(i)}/entry' for i in range(m))}]\n"
    if len(one_line) > 101:
        items = "".join(f"    {name(i)}/entry,\n" for i in range(m))
        one_line = f"  val entries = [\n{items}  ]\n"
    return (
        "// Entry point of a generated compile_large project. It calls every\n"
        "// module's `entry` once, in order, and prints a checksum.\n"
        "module main\n"
        "\n"
        f"{imports}"
        "\n"
        "// The modulus that keeps every value small.\n"
        f"val p = {P}\n"
        "\n"
        "pub fun main()\n"
        f"{one_line}"
        "  val checksum = entries.foldl(0) fn(s, entry) (s * 31 + entry(s)) % p\n"
        "  println(checksum.show)\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.kk").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.kk").write_text(module(i))


if __name__ == "__main__":
    main()
