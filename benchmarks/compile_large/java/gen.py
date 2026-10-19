"""Writes the Java project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is flat, in the default package: Main.java and one class per module, M0000.java to
M<M-1>.java, all compiled by one `javac -d {build}/classes *.java` (langs/java.toml). Each module
class has a nested `record Item`, a nested `sealed interface Shape` with four record variants
matched by a `switch` pattern, and 20 static methods. Only `base` and `entry` are package-private;
everything else is `private`. The output uses 4-space indentation and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"M{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [
        f"""/** Module {i} of a generated compile_large project. */
final class {name(i)} {{
    /** The modulus that keeps every value small. */
    private static final long P = {P};

    private {name(i)}() {{}}

    /** A record that {{@code makeItem}} builds and {{@code itemScore}} reads. */
    private record Item(long id, long size, long weight) {{}}

    /** A sum type that {{@code makeShape}} builds and {{@code area}} matches. */
    private sealed interface Shape permits Circle, Rect, Tri, Empty {{}}

    private record Circle(long r) implements Shape {{}}

    private record Rect(long w, long h) implements Shape {{}}

    private record Tri(long a, long b, long c) implements Shape {{}}

    private record Empty() implements Shape {{}}

    /** The first link of this module's chain, also called by the next module. */
    static long base(long x) {{
        long a = x * {k[0]} + {k[1]};
        long b = a % P;
        return (b * {k[2]} + {k[3]}) % P;
    }}
"""
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
    /** Link {j} of the chain. */
    private static long step{j}(long x) {{
        long y = {prev}(x);
        long a = y * {k[4 * j]} + x;
        long b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P;
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
    /** Builds an item from {{@code x}}. */
    private static Item makeItem(long x) {{
        return new Item(x % {k[56]}, x % 1000 + {k[57]}, x * {k[58]} % P);
    }}

    /** Reads every field of {{@code item}}. */
    private static long itemScore(Item item) {{
        return (item.id() * {k[59]} + item.size() * {k[60]} + item.weight()) % P;
    }}

    /** Picks a shape from {{@code x}}. */
    private static Shape makeShape(long x) {{
        return switch ((int) (x % 4)) {{
            case 0 -> new Circle(x % {k[61]} + 1);
            case 1 -> new Rect(x % {k[62]} + 1, x % {k[63]} + 1);
            case 2 -> new Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1);
            default -> new Empty();
        }};
    }}

    /** The area of {{@code shape}}, in whole units. */
    private static long area(Shape shape) {{
        return switch (shape) {{
            case Circle(long r) -> 3 * r * r;
            case Rect(long w, long h) -> w * h;
            case Tri(long a, long b, long c) -> a * b / 2 + c;
            case Empty() -> {k[67]};
        }};
    }}
"""
    )
    if i > 0:
        out.append(
            f"""
    /** Calls into the previous module. */
    private static long link(long x) {{
        return ({name(i - 1)}.base(x) + {k[68]}) % P;
    }}
"""
        )
    else:
        out.append(
            f"""
    /** The first module has no previous module to call. */
    private static long link(long x) {{
        return (x + {k[68]}) % P;
    }}
"""
        )
    out.append(
        """
    /** The function {@code Main} calls. */
    static long entry(long x) {
        long s = step13(x);
        long r = itemScore(makeItem(s));
        long h = area(makeShape(x));
        long l = link(x);
        return (s + r + h + l) % P;
    }
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    one_line = ", ".join(f"{name(i)}::entry" for i in range(m))
    entries = f"        LongUnaryOperator[] entries = {{{one_line}}};\n"
    if len(entries) > 101:  # 100 columns, plus the newline
        items = "".join(f"            {name(i)}::entry,\n" for i in range(m))
        entries = f"        LongUnaryOperator[] entries = {{\n{items}        }};\n"
    return (
        "import java.util.function.LongUnaryOperator;\n"
        "\n"
        "/**\n"
        " * Entry point of a generated compile_large project. It calls every module's {@code entry}\n"
        " * once, in order, and prints a checksum.\n"
        " */\n"
        "public class Main {\n"
        "    /** The modulus that keeps every value small. */\n"
        f"    private static final long P = {P};\n"
        "\n"
        "    public static void main(String[] args) {\n"
        f"{entries}"
        "        long s = 0;\n"
        "        for (LongUnaryOperator entry : entries) {\n"
        "            s = (s * 31 + entry.applyAsLong(s)) % P;\n"
        "        }\n"
        "        System.out.println(s);\n"
        "    }\n"
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
    (out / "Main.java").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.java").write_text(module(i))


if __name__ == "__main__":
    main()
