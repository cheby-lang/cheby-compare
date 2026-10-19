"""Writes the Odin project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one Odin program: `main.odin` (package main) at the root and one
package per module in its own directory, m0000/m0000.odin to m<M-1>/m<M-1>.odin.
Module i imports module i - 1 by relative path ("../m0000"), and main imports
every module ("m0000"). `odin build .` in the root builds it. The output uses
tabs, as Odin's core library does, and depends only on M. Every item except `base` and
`entry` is @(private) to its package, as in the Rust and Cheby references.
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
    out = [f"// Module {i} of a generated compile_large project.\npackage {name(i)}\n"]
    if i > 0:
        out.append(f'\nimport "../{name(i - 1)}"\n')
    out.append(
        f"""
// The modulus that keeps every value small.
@(private)
P :: {P}

// A record that `make_item` builds and `item_score` reads.
@(private)
Item :: struct {{
\tid:     int,
\tsize:   int,
\tweight: int,
}}

@(private)
Circle :: struct {{
\tr: int,
}}

@(private)
Rect :: struct {{
\tw, h: int,
}}

@(private)
Tri :: struct {{
\ta, b, c: int,
}}

@(private)
Empty :: struct {{}}

// A sum type that `make_shape` builds and `area` matches.
@(private)
Shape :: union {{
\tCircle,
\tRect,
\tTri,
\tEmpty,
}}

// The first link of this module's chain, also called by the next module.
base :: proc(x: int) -> int {{
\ta := x * {k[0]} + {k[1]}
\tb := a % P
\treturn (b * {k[2]} + {k[3]}) % P
}}
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
// Link {j} of the chain.
@(private)
step_{j} :: proc(x: int) -> int {{
\ty := {prev}(x)
\ta := y * {k[4 * j]} + x
\tb := (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P
\tif b % 2 == 0 {{
\t\treturn (a + b) % P
\t}} else {{
\t\treturn (a + b * {k[4 * j + 3]}) % P
\t}}
}}
"""
        )
    out.append(
        f"""
// Builds an item from `x`.
@(private)
make_item :: proc(x: int) -> Item {{
\treturn Item{{id = x % {k[56]}, size = x % 1000 + {k[57]}, weight = x * {k[58]} % P}}
}}

// Reads every field of `item`.
@(private)
item_score :: proc(item: Item) -> int {{
\treturn (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P
}}

// Picks a shape from `x`.
@(private)
make_shape :: proc(x: int) -> Shape {{
\tswitch x % 4 {{
\tcase 0:
\t\treturn Circle{{x % {k[61]} + 1}}
\tcase 1:
\t\treturn Rect{{x % {k[62]} + 1, x % {k[63]} + 1}}
\tcase 2:
\t\treturn Tri{{x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1}}
\tcase:
\t\treturn Empty{{}}
\t}}
}}

// The area of `shape`, in whole units.
@(private)
area :: proc(shape: Shape) -> int {{
\tswitch s in shape {{
\tcase Circle:
\t\treturn 3 * s.r * s.r
\tcase Rect:
\t\treturn s.w * s.h
\tcase Tri:
\t\treturn s.a * s.b / 2 + s.c
\tcase Empty:
\t\treturn {k[67]}
\t}}
\tunreachable()
}}
"""
    )
    if i > 0:
        out.append(
            f"""
// Calls into the previous module.
@(private)
link :: proc(x: int) -> int {{
\treturn ({name(i - 1)}.base(x) + {k[68]}) % P
}}
"""
        )
    else:
        out.append(
            f"""
// The first module has no previous module to call.
@(private)
link :: proc(x: int) -> int {{
\treturn (x + {k[68]}) % P
}}
"""
        )
    out.append(
        """
// The procedure `main` calls.
entry :: proc(x: int) -> int {
\ts := step_13(x)
\tr := item_score(make_item(s))
\th := area(make_shape(x))
\tl := link(x)
\treturn (s + r + h + l) % P
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f'import "{name(i)}"\n' for i in range(m))
    items = "".join(f"\t\t{name(i)}.entry,\n" for i in range(m))
    return (
        "// Entry point of a generated compile_large project. It calls every\n"
        "// module's `entry` once, in order, and prints a checksum.\n"
        "package main\n"
        "\n"
        'import "core:fmt"\n'
        f"{imports}"
        "\n"
        "// The modulus that keeps every value small.\n"
        f"P :: {P}\n"
        "\n"
        "main :: proc() {\n"
        f"\tentries: [{m}]proc(x: int) -> int = {{\n"
        f"{items}"
        "\t}\n"
        "\ts := 0\n"
        "\tfor entry in entries {\n"
        "\t\ts = (s * 31 + entry(s)) % P\n"
        "\t}\n"
        "\tfmt.println(s)\n"
        "}\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.odin").write_text(main_module(m))
    for i in range(m):
        d = out / name(i)
        d.mkdir(exist_ok=True)
        (d / f"{name(i)}.odin").write_text(module(i))


if __name__ == "__main__":
    main()
