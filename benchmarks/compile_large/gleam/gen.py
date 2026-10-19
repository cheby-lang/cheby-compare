"""Writes the Gleam project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one Gleam package named `main` on the Erlang target: gleam.toml,
manifest.toml (gleam_stdlib only, pinned like every other Gleam benchmark),
src/main.gleam and one module per index, src/m0000.gleam to src/m<M-1>.gleam.
The output is in `gleam format` form and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003
P_LITERAL = "1_000_003"  # gleam format writes digit separators

GLEAM_TOML = """name = "main"
version = "1.0.0"
target = "erlang"

[dependencies]
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
"""

MANIFEST_TOML = """# Do not manually edit this file, it is managed by Gleam.
#
# This file locks the dependency versions used, to make your build
# deterministic and to prevent unexpected versions from being included
# in your application.
#
# You should check this file into your source control repository.

packages = [
  { name = "gleam_stdlib", version = "1.0.5", build_tools = ["gleam"], requirements = [], otp_app = "gleam_stdlib", source = "hex", outer_checksum = "CEE5B6C076A85B45F60C585F4316C63EC8B7127C119D5738C3958A9C4D50404E" },
]

[requirements]
gleam_stdlib = { version = ">= 1.0.0 and < 2.0.0" }
"""


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [f"//// Module {i} of a generated compile_large project.\n"]
    if i > 0:
        out.append(f"\nimport {name(i - 1)}\n")
    out.append(
        f"""
/// The modulus that keeps every value small.
const p = {P_LITERAL}

/// A record that `make_item` builds and `item_score` reads.
type Item {{
  Item(id: Int, size: Int, weight: Int)
}}

/// A sum type that `make_shape` builds and `area` matches.
type Shape {{
  Circle(Int)
  Rect(Int, Int)
  Tri(Int, Int, Int)
  Empty
}}

/// The first link of this module's chain, also called by the next module.
pub fn base(x: Int) -> Int {{
  let a = x * {k[0]} + {k[1]}
  let b = a % p
  {{ b * {k[2]} + {k[3]} }} % p
}}
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
/// Link {j} of the chain.
fn step_{j}(x: Int) -> Int {{
  let y = {prev}(x)
  let a = y * {k[4 * j]} + x
  let b = {{ a / {k[4 * j + 1]} + {k[4 * j + 2]} }} % p
  case b % 2 == 0 {{
    True -> {{ a + b }} % p
    False -> {{ a + b * {k[4 * j + 3]} }} % p
  }}
}}
"""
        )
    out.append(
        f"""
/// Builds an item from `x`.
fn make_item(x: Int) -> Item {{
  Item(id: x % {k[56]}, size: x % 1000 + {k[57]}, weight: x * {k[58]} % p)
}}

/// Reads every field of `item`.
fn item_score(item: Item) -> Int {{
  {{ item.id * {k[59]} + item.size * {k[60]} + item.weight }} % p
}}

/// Picks a shape from `x`.
fn make_shape(x: Int) -> Shape {{
  case x % 4 {{
    0 -> Circle(x % {k[61]} + 1)
    1 -> Rect(x % {k[62]} + 1, x % {k[63]} + 1)
    2 -> Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
    _ -> Empty
  }}
}}

/// The area of `shape`, in whole units.
fn area(shape: Shape) -> Int {{
  case shape {{
    Circle(r) -> 3 * r * r
    Rect(w, h) -> w * h
    Tri(a, b, c) -> a * b / 2 + c
    Empty -> {k[67]}
  }}
}}
"""
    )
    if i > 0:
        out.append(
            f"""
/// Calls into the previous module.
fn link(x: Int) -> Int {{
  {{ {name(i - 1)}.base(x) + {k[68]} }} % p
}}
"""
        )
    else:
        out.append(
            f"""
/// The first module has no previous module to call.
fn link(x: Int) -> Int {{
  {{ x + {k[68]} }} % p
}}
"""
        )
    out.append(
        """
/// The function `main` calls.
pub fn entry(x: Int) -> Int {
  let s = step_13(x)
  let r = item_score(make_item(s))
  let h = area(make_shape(x))
  let l = link(x)
  { s + r + h + l } % p
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f"import {name(i)}\n" for i in range(m))
    one_line = f"  let entries = [{', '.join(f'{name(i)}.entry' for i in range(m))}]\n"
    if len(one_line) <= 81:  # gleam format's 80 columns, plus the newline
        entries = one_line
    else:
        items = "".join(f"    {name(i)}.entry,\n" for i in range(m))
        entries = f"  let entries = [\n{items}  ]\n"
    return (
        "//// Entry point of a generated compile_large project. It calls every\n"
        "//// module's `entry` once, in order, and prints a checksum.\n"
        "\n"
        "import gleam/int\n"
        "import gleam/io\n"
        "import gleam/list\n"
        f"{imports}"
        "\n"
        "/// The modulus that keeps every value small.\n"
        f"const p = {P_LITERAL}\n"
        "\n"
        "pub fn main() -> Nil {\n"
        f"{entries}"
        "  let checksum =\n"
        "    list.fold(entries, 0, fn(s, entry) { { s * 31 + entry(s) } % p })\n"
        "  io.println(int.to_string(checksum))\n"
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
    (out / "gleam.toml").write_text(GLEAM_TOML)
    (out / "manifest.toml").write_text(MANIFEST_TOML)
    (src / "main.gleam").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.gleam").write_text(module(i))


if __name__ == "__main__":
    main()
