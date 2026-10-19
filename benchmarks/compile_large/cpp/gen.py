"""Writes the C++ project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one header and one source file per module, m0000.hpp and
m0000.cpp to m<M-1>.hpp and m<M-1>.cpp, plus main.cpp and a Makefile with one
object file per module, built with parallel make (SPEC "Parallelism"). Each
module's items live in `namespace m0000`: `base` and `entry` are declared in the
header, everything else is in an anonymous namespace in the source file. The
output is in clang-format form (Google style with a 4-space indent and 100
columns, like the other C++ implementations) and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def header(i: int) -> str:
    return f"""// Module {i} of a generated compile_large project: its public functions.
#pragma once

#include <cstdint>

namespace {name(i)} {{

// The first link of this module's chain, also called by the next module.
std::int64_t base(std::int64_t x);

// The function `main` calls.
std::int64_t entry(std::int64_t x);

}}  // namespace {name(i)}
"""


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [f"// Module {i} of a generated compile_large project.\n"]
    out.append(f'#include "{name(i)}.hpp"\n\n#include <cstdint>\n#include <variant>\n')
    if i > 0:
        out.append(f'\n#include "{name(i - 1)}.hpp"\n')
    out.append(
        f"""
namespace {name(i)} {{

namespace {{

// The modulus that keeps every value small.
const std::int64_t P = {P};

// A record that `make_item` builds and `item_score` reads.
struct Item {{
    std::int64_t id;
    std::int64_t size;
    std::int64_t weight;
}};

// The variants of `Shape`, a sum type that `make_shape` builds and `area` matches.
struct Circle {{
    std::int64_t r;
}};

struct Rect {{
    std::int64_t w;
    std::int64_t h;
}};

struct Tri {{
    std::int64_t a;
    std::int64_t b;
    std::int64_t c;
}};

struct Empty {{}};

using Shape = std::variant<Circle, Rect, Tri, Empty>;

}}  // namespace

std::int64_t base(std::int64_t x) {{
    std::int64_t a = x * {k[0]} + {k[1]};
    std::int64_t b = a % P;
    return (b * {k[2]} + {k[3]}) % P;
}}

namespace {{
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
// Link {j} of the chain.
std::int64_t step_{j}(std::int64_t x) {{
    std::int64_t y = {prev}(x);
    std::int64_t a = y * {k[4 * j]} + x;
    std::int64_t b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P;
    if (b % 2 == 0) {{
        return (a + b) % P;
    }} else {{
        return (a + b * {k[4 * j + 3]}) % P;
    }}
}}
"""
        )
    out.append(
        f"""
// Builds an item from `x`.
Item make_item(std::int64_t x) {{
    return Item{{.id = x % {k[56]}, .size = x % 1000 + {k[57]}, .weight = x * {k[58]} % P}};
}}

// Reads every field of `item`.
std::int64_t item_score(const Item& item) {{
    return (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P;
}}

// Picks a shape from `x`.
Shape make_shape(std::int64_t x) {{
    switch (x % 4) {{
        case 0:
            return Circle{{x % {k[61]} + 1}};
        case 1:
            return Rect{{x % {k[62]} + 1, x % {k[63]} + 1}};
        case 2:
            return Tri{{x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1}};
        default:
            return Empty{{}};
    }}
}}

// The visitor that `area` passes to `std::visit`: one overload per variant of `Shape`.
struct Area {{
    std::int64_t operator()(const Circle& s) const {{ return 3 * s.r * s.r; }}
    std::int64_t operator()(const Rect& s) const {{ return s.w * s.h; }}
    std::int64_t operator()(const Tri& s) const {{ return s.a * s.b / 2 + s.c; }}
    std::int64_t operator()(const Empty&) const {{ return {k[67]}; }}
}};

// The area of `shape`, in whole units.
std::int64_t area(const Shape& shape) {{ return std::visit(Area{{}}, shape); }}
"""
    )
    if i > 0:
        out.append(
            f"""
// Calls into the previous module.
std::int64_t link(std::int64_t x) {{ return ({name(i - 1)}::base(x) + {k[68]}) % P; }}
"""
        )
    else:
        out.append(
            f"""
// The first module has no previous module to call.
std::int64_t link(std::int64_t x) {{ return (x + {k[68]}) % P; }}
"""
        )
    out.append(
        f"""
}}  // namespace

std::int64_t entry(std::int64_t x) {{
    std::int64_t s = step_13(x);
    std::int64_t r = item_score(make_item(s));
    std::int64_t h = area(make_shape(x));
    std::int64_t l = link(x);
    return (s + r + h + l) % P;
}}

}}  // namespace {name(i)}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    includes = "".join(f'#include "{name(i)}.hpp"\n' for i in range(m))
    decl = f"    const std::array<std::int64_t (*)(std::int64_t), {m}> entries = {{"
    names = [f"{name(i)}::entry" for i in range(m)]
    one_line = ", ".join(names)
    if len(decl) + len(one_line) + 2 <= 100:  # clang-format's 100 columns
        entries = f"{decl}{one_line}}};\n"
    else:  # clang-format's layout of a braced list with a trailing comma
        lines = -(-m // 6) if m >= 5 else m  # at most six to a line; columns from five items on
        width = -(-m // lines)
        rows = [", ".join(names[r : r + width]) for r in range(0, m, width)]
        items = "".join(f"        {row},\n" for row in rows)
        entries = f"{decl}\n{items}    }};\n"
    return (
        "// Entry point of a generated compile_large project. It calls every module's `entry`\n"
        "// once, in order, and prints a checksum.\n"
        "#include <array>\n"
        "#include <cstdint>\n"
        "#include <iostream>\n"
        "\n"
        f"{includes}"
        "\n"
        "// The modulus that keeps every value small.\n"
        f"const std::int64_t P = {P};\n"
        "\n"
        "int main() {\n"
        f"{entries}"
        "    std::int64_t s = 0;\n"
        "    for (auto entry : entries) {\n"
        "        s = (s * 31 + entry(s)) % P;\n"
        "    }\n"
        "    std::cout << s << '\\n';\n"
        "}\n"
    )


def makefile(m: int) -> str:
    mods = " \\\n".join(f"\t{name(i)}" for i in range(m))
    deps = "".join(
        f"$(OUT)/{name(i)}.o: {name(i)}.hpp"
        + (f" {name(i - 1)}.hpp" if i > 0 else "")
        + "\n"
        for i in range(m)
    )
    return (
        "# Generated compile_large project: one object file per module, linked into $(OUT)/main.\n"
        "# CXX and CXXFLAGS come from the environment (langs/cpp.toml). Build with `make -jN`.\n"
        "OUT ?= .\n"
        "\n"
        "MODULES = \\\n"
        f"{mods}\n"
        "\n"
        "OBJS = $(OUT)/main.o $(MODULES:%=$(OUT)/%.o)\n"
        "\n"
        "$(OUT)/main: $(OBJS)\n"
        "\t$(CXX) $(CXXFLAGS) -o $@ $(OBJS)\n"
        "\n"
        "$(OUT)/%.o: %.cpp\n"
        "\t$(CXX) $(CXXFLAGS) -c -o $@ $<\n"
        "\n"
        "$(OUT)/main.o: $(MODULES:%=%.hpp)\n"
        f"{deps}"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "Makefile").write_text(makefile(m))
    (out / "main.cpp").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.hpp").write_text(header(i))
        (out / f"{name(i)}.cpp").write_text(module(i))


if __name__ == "__main__":
    main()
