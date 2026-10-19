"""Writes the Go project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one Go module named `main`: go.mod, main.go (package main) at the
root and one package per module in its own directory, m0000/m0000.go to
m<M-1>/m<M-1>.go. Module i imports module i - 1 ("main/m0000"), and main imports
every module. Only Base and Entry are exported. Shape is a sealed interface (an
unexported marker method) with four struct types, matched with a type switch.
`go build` in the root builds it. The output is gofmt-clean and depends only on M.
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
    out = [f"// Package {name(i)} is module {i} of a generated compile_large project.\n"]
    out.append(f"package {name(i)}\n")
    if i > 0:
        out.append(f'\nimport "main/{name(i - 1)}"\n')
    out.append(
        f"""
// p is the modulus that keeps every value small.
const p = {P}

// item is a record that makeItem builds and itemScore reads.
type item struct {{
\tid     int
\tsize   int
\tweight int
}}

// shape is a sum type that makeShape builds and area matches.
type shape interface {{
\tisShape()
}}

type circle struct{{ r int }}

type rect struct{{ w, h int }}

type tri struct{{ a, b, c int }}

type empty struct{{}}

func (circle) isShape() {{}}
func (rect) isShape()   {{}}
func (tri) isShape()    {{}}
func (empty) isShape()  {{}}

// Base is the first link of this module's chain, also called by the next module.
func Base(x int) int {{
\ta := x*{k[0]} + {k[1]}
\tb := a % p
\treturn (b*{k[2]} + {k[3]}) % p
}}
"""
    )
    for j in range(1, 14):
        prev = "Base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
// step{j} is link {j} of the chain.
func step{j}(x int) int {{
\ty := {prev}(x)
\ta := y*{k[4 * j]} + x
\tb := (a/{k[4 * j + 1]} + {k[4 * j + 2]}) % p
\tif b%2 == 0 {{
\t\treturn (a + b) % p
\t}} else {{
\t\treturn (a + b*{k[4 * j + 3]}) % p
\t}}
}}
"""
        )
    out.append(
        f"""
// makeItem builds an item from x.
func makeItem(x int) item {{
\treturn item{{
\t\tid:     x % {k[56]},
\t\tsize:   x%1000 + {k[57]},
\t\tweight: x * {k[58]} % p,
\t}}
}}

// itemScore reads every field of it.
func itemScore(it item) int {{
\treturn (it.id*{k[59]} + it.size*{k[60]} + it.weight) % p
}}

// makeShape picks a shape from x.
func makeShape(x int) shape {{
\tswitch x % 4 {{
\tcase 0:
\t\treturn circle{{x%{k[61]} + 1}}
\tcase 1:
\t\treturn rect{{x%{k[62]} + 1, x%{k[63]} + 1}}
\tcase 2:
\t\treturn tri{{x%{k[64]} + 1, x%{k[65]} + 1, x%{k[66]} + 1}}
\tdefault:
\t\treturn empty{{}}
\t}}
}}

// area is the area of s, in whole units.
func area(s shape) int {{
\tswitch s := s.(type) {{
\tcase circle:
\t\treturn 3 * s.r * s.r
\tcase rect:
\t\treturn s.w * s.h
\tcase tri:
\t\treturn s.a*s.b/2 + s.c
\tcase empty:
\t\treturn {k[67]}
\t}}
\tpanic("unknown shape")
}}
"""
    )
    if i > 0:
        out.append(
            f"""
// link calls into the previous module.
func link(x int) int {{
\treturn ({name(i - 1)}.Base(x) + {k[68]}) % p
}}
"""
        )
    else:
        out.append(
            f"""
// link stands in for the call into the previous module, which the first module lacks.
func link(x int) int {{
\treturn (x + {k[68]}) % p
}}
"""
        )
    out.append(
        """
// Entry is the function main calls.
func Entry(x int) int {
\ts := step13(x)
\tr := itemScore(makeItem(s))
\th := area(makeShape(x))
\tl := link(x)
\treturn (s + r + h + l) % p
}
"""
    )
    return "".join(out)


def main_go(m: int) -> str:
    imports = "".join(f'\t"main/{name(i)}"\n' for i in range(m))
    entries = "".join(f"\t\t{name(i)}.Entry,\n" for i in range(m))
    return (
        "// Entry point of a generated compile_large project. It calls every module's Entry\n"
        "// once, in order, and prints a checksum.\n"
        "package main\n"
        "\n"
        "import (\n"
        '\t"fmt"\n'
        "\n"
        f"{imports}"
        ")\n"
        "\n"
        "// p is the modulus that keeps every value small.\n"
        f"const p = {P}\n"
        "\n"
        "func main() {\n"
        "\tentries := []func(int) int{\n"
        f"{entries}"
        "\t}\n"
        "\ts := 0\n"
        "\tfor _, entry := range entries {\n"
        "\t\ts = (s*31 + entry(s)) % p\n"
        "\t}\n"
        "\tfmt.Println(s)\n"
        "}\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if not 1 <= m <= 9999:
        sys.exit("M must be between 1 and 9999")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "go.mod").write_text("module main\n\ngo 1.27\n")
    (out / "main.go").write_text(main_go(m))
    for i in range(m):
        d = out / name(i)
        d.mkdir(exist_ok=True)
        (d / f"{name(i)}.go").write_text(module(i))


if __name__ == "__main__":
    main()
