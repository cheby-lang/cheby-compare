"""Writes the Zig project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is src/main.zig and one file per module, src/m0000.zig to
src/m<M-1>.zig, pulled in with @import. There is no build.zig: langs/zig.toml
builds src/main.zig with plain `zig build-exe`. Integers are u64, since every
value is non-negative, so `/` and `%` are the plain unsigned operators. The
output is in `zig fmt` form and depends only on M.
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
        out.append(f'\nconst {name(i - 1)} = @import("{name(i - 1)}.zig");\n')
    out.append(
        f"""
/// The modulus that keeps every value small.
const modulus: u64 = {P};

/// A record that `makeItem` builds and `itemScore` reads.
const Item = struct {{
    id: u64,
    size: u64,
    weight: u64,
}};

/// A sum type that `makeShape` builds and `area` matches.
const Shape = union(enum) {{
    circle: u64,
    rect: struct {{ w: u64, h: u64 }},
    tri: struct {{ a: u64, b: u64, c: u64 }},
    empty,
}};

/// The first link of this module's chain, also called by the next module.
pub fn base(x: u64) u64 {{
    const a = x * {k[0]} + {k[1]};
    const b = a % modulus;
    return (b * {k[2]} + {k[3]}) % modulus;
}}
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
/// Link {j} of the chain.
fn step{j}(x: u64) u64 {{
    const y = {prev}(x);
    const a = y * {k[4 * j]} + x;
    const b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % modulus;
    if (b % 2 == 0) {{
        return (a + b) % modulus;
    }} else {{
        return (a + b * {k[4 * j + 3]}) % modulus;
    }}
}}
"""
        )
    out.append(
        f"""
/// Builds an item from `x`.
fn makeItem(x: u64) Item {{
    return .{{
        .id = x % {k[56]},
        .size = x % 1000 + {k[57]},
        .weight = x * {k[58]} % modulus,
    }};
}}

/// Reads every field of `item`.
fn itemScore(item: Item) u64 {{
    return (item.id * {k[59]} + item.size * {k[60]} + item.weight) % modulus;
}}

/// Picks a shape from `x`.
fn makeShape(x: u64) Shape {{
    return switch (x % 4) {{
        0 => .{{ .circle = x % {k[61]} + 1 }},
        1 => .{{ .rect = .{{ .w = x % {k[62]} + 1, .h = x % {k[63]} + 1 }} }},
        2 => .{{ .tri = .{{ .a = x % {k[64]} + 1, .b = x % {k[65]} + 1, .c = x % {k[66]} + 1 }} }},
        else => .empty,
    }};
}}

/// The area of `shape`, in whole units.
fn area(shape: Shape) u64 {{
    return switch (shape) {{
        .circle => |r| 3 * r * r,
        .rect => |rect| rect.w * rect.h,
        .tri => |tri| tri.a * tri.b / 2 + tri.c,
        .empty => {k[67]},
    }};
}}
"""
    )
    if i > 0:
        out.append(
            f"""
/// Calls into the previous module.
fn link(x: u64) u64 {{
    return ({name(i - 1)}.base(x) + {k[68]}) % modulus;
}}
"""
        )
    else:
        out.append(
            f"""
/// The first module has no previous module to call.
fn link(x: u64) u64 {{
    return (x + {k[68]}) % modulus;
}}
"""
        )
    out.append(
        """
/// The function `main` calls.
pub fn entry(x: u64) u64 {
    const s = step13(x);
    const r = itemScore(makeItem(s));
    const h = area(makeShape(x));
    const l = link(x);
    return (s + r + h + l) % modulus;
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f'const {name(i)} = @import("{name(i)}.zig");\n' for i in range(m))
    items = "".join(f"        {name(i)}.entry,\n" for i in range(m))
    return (
        "//! Entry point of a generated compile_large project. It calls every\n"
        "//! module's `entry` once, in order, and prints a checksum.\n"
        "\n"
        'const std = @import("std");\n'
        f"{imports}"
        "\n"
        "/// The modulus that keeps every value small.\n"
        f"const modulus: u64 = {P};\n"
        "\n"
        "pub fn main(init: std.process.Init) !void {\n"
        "    const entries = [_]*const fn (u64) u64{\n"
        f"{items}"
        "    };\n"
        "    var s: u64 = 0;\n"
        "    for (entries) |entry| {\n"
        "        s = (s * 31 + entry(s)) % modulus;\n"
        "    }\n"
        "\n"
        "    var stdout_buffer: [64]u8 = undefined;\n"
        "    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);\n"
        "    const stdout = &stdout_writer.interface;\n"
        '    try stdout.print("{d}\\n", .{s});\n'
        "    try stdout.flush();\n"
        "}\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if not 1 <= m <= 9999:
        sys.exit("M must be between 1 and 9999")
    out = Path(sys.argv[2])
    src = out / "src"
    src.mkdir(parents=True, exist_ok=True)
    (src / "main.zig").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.zig").write_text(module(i))


if __name__ == "__main__":
    main()
