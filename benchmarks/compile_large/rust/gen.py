"""Writes the Rust project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one crate named `main`: Cargo.toml, src/main.rs and one
module per index, src/m0000.rs to src/m<M-1>.rs. The output is in rustfmt
form and depends only on M.
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
        out.append(f"\nuse crate::{name(i - 1)};\n")
    out.append(
        f"""
/// The modulus that keeps every value small.
const P: i64 = {P};

/// A record that `make_item` builds and `item_score` reads.
struct Item {{
    id: i64,
    size: i64,
    weight: i64,
}}

/// A sum type that `make_shape` builds and `area` matches.
enum Shape {{
    Circle(i64),
    Rect(i64, i64),
    Tri(i64, i64, i64),
    Empty,
}}

/// The first link of this module's chain, also called by the next module.
pub fn base(x: i64) -> i64 {{
    let a = x * {k[0]} + {k[1]};
    let b = a % P;
    (b * {k[2]} + {k[3]}) % P
}}
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
/// Link {j} of the chain.
fn step_{j}(x: i64) -> i64 {{
    let y = {prev}(x);
    let a = y * {k[4 * j]} + x;
    let b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P;
    if b % 2 == 0 {{
        (a + b) % P
    }} else {{
        (a + b * {k[4 * j + 3]}) % P
    }}
}}
"""
        )
    out.append(
        f"""
/// Builds an item from `x`.
fn make_item(x: i64) -> Item {{
    Item {{
        id: x % {k[56]},
        size: x % 1000 + {k[57]},
        weight: x * {k[58]} % P,
    }}
}}

/// Reads every field of `item`.
fn item_score(item: &Item) -> i64 {{
    (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P
}}

/// Picks a shape from `x`.
fn make_shape(x: i64) -> Shape {{
    match x % 4 {{
        0 => Shape::Circle(x % {k[61]} + 1),
        1 => Shape::Rect(x % {k[62]} + 1, x % {k[63]} + 1),
        2 => Shape::Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1),
        _ => Shape::Empty,
    }}
}}

/// The area of `shape`, in whole units.
fn area(shape: &Shape) -> i64 {{
    match shape {{
        Shape::Circle(r) => 3 * r * r,
        Shape::Rect(w, h) => w * h,
        Shape::Tri(a, b, c) => a * b / 2 + c,
        Shape::Empty => {k[67]},
    }}
}}
"""
    )
    if i > 0:
        out.append(
            f"""
/// Calls into the previous module.
fn link(x: i64) -> i64 {{
    ({name(i - 1)}::base(x) + {k[68]}) % P
}}
"""
        )
    else:
        out.append(
            f"""
/// The first module has no previous module to call.
fn link(x: i64) -> i64 {{
    (x + {k[68]}) % P
}}
"""
        )
    out.append(
        """
/// The function `main` calls.
pub fn entry(x: i64) -> i64 {
    let s = step_13(x);
    let r = item_score(&make_item(s));
    let h = area(&make_shape(x));
    let l = link(x);
    (s + r + h + l) % P
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    mods = "".join(f"mod {name(i)};\n" for i in range(m))
    one_line = ", ".join(f"{name(i)}::entry" for i in range(m))
    entries = f"    let entries: [fn(i64) -> i64; {m}] = [{one_line}];\n"
    if len(entries) > 101:  # rustfmt's 100 columns, plus the newline
        items = "".join(f"        {name(i)}::entry,\n" for i in range(m))
        entries = f"    let entries: [fn(i64) -> i64; {m}] = [\n{items}    ];\n"
    return (
        "//! Entry point of a generated compile_large project. It calls every\n"
        "//! module's `entry` once, in order, and prints a checksum.\n"
        "\n"
        f"{mods}"
        "\n"
        "/// The modulus that keeps every value small.\n"
        f"const P: i64 = {P};\n"
        "\n"
        "fn main() {\n"
        f"{entries}"
        "    let checksum = entries.iter().fold(0, |s, entry| (s * 31 + entry(s)) % P);\n"
        '    println!("{checksum}");\n'
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
    (out / "Cargo.toml").write_text(
        '[package]\nname = "main"\nversion = "0.1.0"\nedition = "2024"\n\n[profile.release]\n'
    )
    (src / "main.rs").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.rs").write_text(module(i))


if __name__ == "__main__":
    main()
