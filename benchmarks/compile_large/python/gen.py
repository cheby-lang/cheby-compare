"""Writes the Python project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is main.py and one module per index, m0000.py to m<M-1>.py,
side by side. The output depends only on M.
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
    out = [f"# Module {i} of a generated compile_large project.\n\n"]
    out.append("from dataclasses import dataclass\n")
    if i > 0:
        out.append(f"\nimport {name(i - 1)}\n")
    out.append(
        f'''
# The modulus that keeps every value small.
P = {P}


# A record that make_item builds and item_score reads.
@dataclass
class Item:
    id: int
    size: int
    weight: int


@dataclass
class Circle:
    r: int


@dataclass
class Rect:
    w: int
    h: int


@dataclass
class Tri:
    a: int
    b: int
    c: int


@dataclass
class Empty:
    pass


type Shape = Circle | Rect | Tri | Empty


# The first link of this module's chain, also called by the next module.
def base(x: int) -> int:
    a = x * {k[0]} + {k[1]}
    b = a % P
    return (b * {k[2]} + {k[3]}) % P
'''
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f'''

# Link {j} of the chain.
def step_{j}(x: int) -> int:
    y = {prev}(x)
    a = y * {k[4 * j]} + x
    b = (a // {k[4 * j + 1]} + {k[4 * j + 2]}) % P
    if b % 2 == 0:
        return (a + b) % P
    return (a + b * {k[4 * j + 3]}) % P
'''
        )
    out.append(
        f'''

# Builds an item from x.
def make_item(x: int) -> Item:
    return Item(id=x % {k[56]}, size=x % 1000 + {k[57]}, weight=x * {k[58]} % P)


# Reads every field of item.
def item_score(item: Item) -> int:
    return (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P


# Picks a shape from x.
def make_shape(x: int) -> Shape:
    match x % 4:
        case 0:
            return Circle(x % {k[61]} + 1)
        case 1:
            return Rect(x % {k[62]} + 1, x % {k[63]} + 1)
        case 2:
            return Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
        case _:
            return Empty()


# The area of shape, in whole units.
def area(shape: Shape) -> int:
    match shape:
        case Circle(r):
            return 3 * r * r
        case Rect(w, h):
            return w * h
        case Tri(a, b, c):
            return a * b // 2 + c
        case Empty():
            return {k[67]}
'''
    )
    if i > 0:
        out.append(
            f'''

# Calls into the previous module.
def link(x: int) -> int:
    return ({name(i - 1)}.base(x) + {k[68]}) % P
'''
        )
    else:
        out.append(
            f'''

# The first module has no previous module to call.
def link(x: int) -> int:
    return (x + {k[68]}) % P
'''
        )
    out.append(
        '''

# The function main calls.
def entry(x: int) -> int:
    s = step_13(x)
    r = item_score(make_item(s))
    h = area(make_shape(x))
    l = link(x)
    return (s + r + h + l) % P
'''
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f"import {name(i)}\n" for i in range(m))
    items = "".join(f"    {name(i)}.entry,\n" for i in range(m))
    return (
        "# Entry point of a generated compile_large project.\n"
        "#\n"
        "# It calls every module's entry once, in order, and prints a checksum.\n"
        "\n"
        f"{imports}"
        "\n"
        "# The modulus that keeps every value small.\n"
        f"P = {P}\n"
        "\n"
        "ENTRIES = [\n"
        f"{items}"
        "]\n"
        "\n"
        "\n"
        "def main() -> None:\n"
        "    s = 0\n"
        "    for entry in ENTRIES:\n"
        "        s = (s * 31 + entry(s)) % P\n"
        "    print(s)\n"
        "\n"
        "\n"
        'if __name__ == "__main__":\n'
        "    main()\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.py").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.py").write_text(module(i))


if __name__ == "__main__":
    main()
