"""Writes the Nim project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is main.nim, the entry file, and one module per index, m0000.nim
to m<M-1>.nim, side by side. Module i imports module i - 1 only. `base` and
`entry` are exported with `*`; everything else stays private. Item is an
object and Shape an object variant (a `case` object). The output depends only
on M.
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
    out = [f"## Module {i} of a generated compile_large project.\n"]
    if i > 0:
        out.append(f"\nimport {name(i - 1)}\n")
    out.append(
        f"""
const P = {P} ## The modulus that keeps every value small.

type
  Item = object ## A record that `makeItem` builds and `itemScore` reads.
    id, size, weight: int

  ShapeKind = enum
    skCircle, skRect, skTri, skEmpty

  Shape = object ## A sum type that `makeShape` builds and `area` matches.
    case kind: ShapeKind
    of skCircle:
      r: int
    of skRect:
      w, h: int
    of skTri:
      a, b, c: int
    of skEmpty:
      discard

proc base*(x: int): int =
  ## The first link of this module's chain, also called by the next module.
  let a = x * {k[0]} + {k[1]}
  let b = a mod P
  (b * {k[2]} + {k[3]}) mod P
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
proc step{j}(x: int): int =
  ## Link {j} of the chain.
  let y = {prev}(x)
  let a = y * {k[4 * j]} + x
  let b = (a div {k[4 * j + 1]} + {k[4 * j + 2]}) mod P
  if b mod 2 == 0:
    (a + b) mod P
  else:
    (a + b * {k[4 * j + 3]}) mod P
"""
        )
    out.append(
        f"""
proc makeItem(x: int): Item =
  ## Builds an item from `x`.
  Item(id: x mod {k[56]}, size: x mod 1000 + {k[57]}, weight: x * {k[58]} mod P)

proc itemScore(item: Item): int =
  ## Reads every field of `item`.
  (item.id * {k[59]} + item.size * {k[60]} + item.weight) mod P

proc makeShape(x: int): Shape =
  ## Picks a shape from `x`.
  case x mod 4
  of 0:
    Shape(kind: skCircle, r: x mod {k[61]} + 1)
  of 1:
    Shape(kind: skRect, w: x mod {k[62]} + 1, h: x mod {k[63]} + 1)
  of 2:
    Shape(kind: skTri, a: x mod {k[64]} + 1, b: x mod {k[65]} + 1, c: x mod {k[66]} + 1)
  else:
    Shape(kind: skEmpty)

proc area(shape: Shape): int =
  ## The area of `shape`, in whole units.
  case shape.kind
  of skCircle: 3 * shape.r * shape.r
  of skRect: shape.w * shape.h
  of skTri: shape.a * shape.b div 2 + shape.c
  of skEmpty: {k[67]}
"""
    )
    if i > 0:
        out.append(
            f"""
proc link(x: int): int =
  ## Calls into the previous module.
  ({name(i - 1)}.base(x) + {k[68]}) mod P
"""
        )
    else:
        out.append(
            f"""
proc link(x: int): int =
  ## The first module has no previous module to call.
  (x + {k[68]}) mod P
"""
        )
    out.append(
        """
proc entry*(x: int): int =
  ## The function `main` calls.
  let s = step13(x)
  let r = itemScore(makeItem(s))
  let h = area(makeShape(x))
  let l = link(x)
  (s + r + h + l) mod P
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f"import {name(i)}\n" for i in range(m))
    one_line = ", ".join(f"{name(i)}.entry" for i in range(m))
    entries = f"let entries = [{one_line}]\n"
    if len(entries) > 81:  # nimpretty's 80 columns, plus the newline
        items = "".join(f"  {name(i)}.entry,\n" for i in range(m))
        entries = f"let entries = [\n{items}]\n"
    return (
        "## Entry point of a generated compile_large project. It calls every\n"
        "## module's `entry` once, in order, and prints a checksum.\n"
        "\n"
        f"{imports}"
        "\n"
        f"const P = {P} ## The modulus that keeps every value small.\n"
        "\n"
        f"{entries}"
        "var checksum = 0\n"
        "for entry in entries:\n"
        "  checksum = (checksum * 31 + entry(checksum)) mod P\n"
        "echo checksum\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.nim").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.nim").write_text(module(i))


if __name__ == "__main__":
    main()
