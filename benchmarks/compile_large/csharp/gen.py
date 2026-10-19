"""Writes the C# project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one `dotnet new console` project named `main` (main.csproj, net10.0, the same file
as every other C# implementation here), built by langs/csharp.toml's `dotnet publish`. Program.cs
holds the top-level statements of main, and each module is one `static class M0000` in its own
file, M0000.cs to M<M-1>.cs, with a nested `record Item`, a nested `abstract record Shape` with
four derived records matched by a `switch` expression, and 20 static methods. Only `Base` and
`Entry` are `internal`; everything else is `private`. The output follows the `dotnet format`
style (4-space indentation, braces on their own lines) and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003

CSPROJ = """<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

</Project>
"""


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"M{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [
        f"""/// <summary>Module {i} of a generated compile_large project.</summary>
internal static class {name(i)}
{{
    /// <summary>The modulus that keeps every value small.</summary>
    private const long P = {P};

    /// <summary>A record that MakeItem builds and ItemScore reads.</summary>
    private sealed record Item(long Id, long Size, long Weight);

    /// <summary>A sum type that MakeShape builds and Area matches.</summary>
    private abstract record Shape;

    private sealed record Circle(long R) : Shape;

    private sealed record Rect(long W, long H) : Shape;

    private sealed record Tri(long A, long B, long C) : Shape;

    private sealed record Empty : Shape;

    /// <summary>The first link of this module's chain, also called by the next module.</summary>
    internal static long Base(long x)
    {{
        long a = x * {k[0]} + {k[1]};
        long b = a % P;
        return (b * {k[2]} + {k[3]}) % P;
    }}
"""
    ]
    for j in range(1, 14):
        prev = "Base" if j == 1 else f"Step{j - 1}"
        out.append(
            f"""
    /// <summary>Link {j} of the chain.</summary>
    private static long Step{j}(long x)
    {{
        long y = {prev}(x);
        long a = y * {k[4 * j]} + x;
        long b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P;
        if (b % 2 == 0)
        {{
            return (a + b) % P;
        }}
        else
        {{
            return (a + b * {k[4 * j + 3]}) % P;
        }}
    }}
"""
        )
    out.append(
        f"""
    /// <summary>Builds an item from x.</summary>
    private static Item MakeItem(long x)
    {{
        return new Item(x % {k[56]}, x % 1000 + {k[57]}, x * {k[58]} % P);
    }}

    /// <summary>Reads every field of the item.</summary>
    private static long ItemScore(Item item)
    {{
        return (item.Id * {k[59]} + item.Size * {k[60]} + item.Weight) % P;
    }}

    /// <summary>Picks a shape from x.</summary>
    private static Shape MakeShape(long x)
    {{
        return (x % 4) switch
        {{
            0 => new Circle(x % {k[61]} + 1),
            1 => new Rect(x % {k[62]} + 1, x % {k[63]} + 1),
            2 => new Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1),
            _ => new Empty(),
        }};
    }}

    /// <summary>The area of the shape, in whole units.</summary>
    private static long Area(Shape shape)
    {{
        return shape switch
        {{
            Circle(var r) => 3 * r * r,
            Rect(var w, var h) => w * h,
            Tri(var a, var b, var c) => a * b / 2 + c,
            Empty => {k[67]},
            _ => throw new ArgumentOutOfRangeException(nameof(shape)),
        }};
    }}
"""
    )
    if i > 0:
        out.append(
            f"""
    /// <summary>Calls into the previous module.</summary>
    private static long Link(long x)
    {{
        return ({name(i - 1)}.Base(x) + {k[68]}) % P;
    }}
"""
        )
    else:
        out.append(
            f"""
    /// <summary>The first module has no previous module to call.</summary>
    private static long Link(long x)
    {{
        return (x + {k[68]}) % P;
    }}
"""
        )
    out.append(
        """
    /// <summary>The function main calls.</summary>
    internal static long Entry(long x)
    {
        long s = Step13(x);
        long r = ItemScore(MakeItem(s));
        long h = Area(MakeShape(x));
        long l = Link(x);
        return (s + r + h + l) % P;
    }
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    one_line = ", ".join(f"{name(i)}.Entry" for i in range(m))
    entries = f"Func<long, long>[] entries = [{one_line}];\n"
    if len(entries) > 101:  # 100 columns, plus the newline
        items = "".join(f"    {name(i)}.Entry,\n" for i in range(m))
        entries = f"Func<long, long>[] entries =\n[\n{items}];\n"
    return (
        "// Entry point of a generated compile_large project. It calls every module's Entry once,\n"
        "// in order, and prints a checksum.\n"
        "\n"
        "// The modulus that keeps every value small.\n"
        f"const long P = {P};\n"
        "\n"
        f"{entries}"
        "long s = 0;\n"
        "foreach (Func<long, long> entry in entries)\n"
        "{\n"
        "    s = (s * 31 + entry(s)) % P;\n"
        "}\n"
        "Console.WriteLine(s);\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if not 1 <= m <= 9999:
        sys.exit("M must be between 1 and 9999")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.csproj").write_text(CSPROJ)
    (out / "Program.cs").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.cs").write_text(module(i))


if __name__ == "__main__":
    main()
