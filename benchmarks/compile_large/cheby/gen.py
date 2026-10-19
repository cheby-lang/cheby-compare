"""Writes the Cheby project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is a package named `app`: cheby.toml, src/main.cheby and one
module per index, src/m0000.cheby to src/m<M-1>.cheby. The output depends
only on M. It follows the style of docs/examples by hand, because `cheby fmt`
is not implemented yet (M5).

Only `base` and `entry` are used outside their module, so every other item of
a module is `priv` (D-162), as the examples do for their helpers.
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
    out = [f"//! Module {i} of a generated compile_large project.\n"]
    if i > 0:
        out.append(f"\nimport app::{name(i - 1)}\n")
    out.append(
        f"""
/// The modulus that keeps every value small.
priv const modulus: Int = {P}

/// A record that `make_item` builds and `item_score` reads.
priv type Item {{ id: Int, size: Int, weight: Int }}

/// A sum type that `make_shape` builds and `area` matches.
priv type Shape {{
  Circle(Int),
  Rect(Int, Int),
  Tri(Int, Int, Int),
  Empty,
}}

/// The first link of this module's chain, also called by the next module.
fn base(x: Int) -> Int {{
  let a = x * {k[0]} + {k[1]}
  let b = a % modulus
  (b * {k[2]} + {k[3]}) % modulus
}}
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
/// Link {j} of the chain.
priv fn step_{j}(x: Int) -> Int {{
  let y = {prev}(x)
  let a = y * {k[4 * j]} + x
  let b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % modulus
  case b % 2 {{
    0 => (a + b) % modulus
    _ => (a + b * {k[4 * j + 3]}) % modulus
  }}
}}
"""
        )
    out.append(
        f"""
/// Builds an item from `x`.
priv fn make_item(x: Int) -> Item {{
  Item {{ id: x % {k[56]}, size: x % 1000 + {k[57]}, weight: x * {k[58]} % modulus }}
}}

/// Reads every field of `item`.
priv fn item_score(item: Item) -> Int {{
  (item.id * {k[59]} + item.size * {k[60]} + item.weight) % modulus
}}

/// Picks a shape from `x`.
priv fn make_shape(x: Int) -> Shape {{
  case x % 4 {{
    0 => Circle(x % {k[61]} + 1)
    1 => Rect(x % {k[62]} + 1, x % {k[63]} + 1)
    2 => Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
    _ => Empty
  }}
}}

/// The area of `shape`, in whole units.
priv fn area(shape: Shape) -> Int {{
  case shape {{
    Circle(r) => 3 * r * r
    Rect(w, h) => w * h
    Tri(a, b, c) => a * b / 2 + c
    Empty => {k[67]}
  }}
}}
"""
    )
    if i > 0:
        out.append(
            f"""
/// Calls into the previous module.
priv fn link(x: Int) -> Int {{
  ({name(i - 1)}::base(x) + {k[68]}) % modulus
}}
"""
        )
    else:
        out.append(
            f"""
/// The first module has no previous module to call.
priv fn link(x: Int) -> Int {{
  (x + {k[68]}) % modulus
}}
"""
        )
    out.append(
        """
/// The function `main` calls.
fn entry(x: Int) -> Int {
  let s = step_13(x)
  let r = item_score(make_item(s))
  let h = area(make_shape(x))
  let l = link(x)
  (s + r + h + l) % modulus
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f"import app::{name(i)}\n" for i in range(m))
    one_line = ", ".join(f"{name(i)}::entry" for i in range(m))
    entries = f"  let entries = [{one_line}]\n"
    # `cheby fmt` is not implemented yet (M5). Follow the style of the
    # examples: one line up to 100 columns, else one item per line.
    if len(entries) > 101:
        items = "".join(f"    {name(i)}::entry,\n" for i in range(m))
        entries = f"  let entries = [\n{items}  ]\n"
    return (
        "//! Entry point of a generated compile_large project. It calls every\n"
        "//! module's `entry` once, in order, and prints a checksum.\n"
        "\n"
        "import std::io\n"
        "import std::list\n"
        f"{imports}"
        "\n"
        "/// The modulus that keeps every value small.\n"
        f"const modulus: Int = {P}\n"
        "\n"
        "fn main() {\n"
        f"{entries}"
        "  let checksum = list::fold(entries, 0, fn(s, entry) { (s * 31 + entry(s)) % modulus })\n"
        '  io::println("{checksum}")\n'
        "}\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    src = out / "src"
    src.mkdir(parents=True, exist_ok=True)
    (out / "cheby.toml").write_text('name = "app"\nversion = "0.1.0"\n')
    (src / "main.cheby").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.cheby").write_text(module(i))


if __name__ == "__main__":
    main()
