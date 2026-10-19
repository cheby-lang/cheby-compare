"""Writes the Swift project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one SwiftPM package named `main` with one executable target, also `main`:
Package.swift, Sources/main/main.swift and one file per module, Sources/main/m0000.swift to
Sources/main/m<M-1>.swift. Each file wraps its module's items in a caseless `enum M0000` used as
a namespace (one Swift module for the whole project). The output is in swift-format's default
style and depends only on M.
"""

import sys
from pathlib import Path

P = "1_000_003"  # written with swift-format's digit grouping


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def type_name(i: int) -> str:
    return f"M{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [
        f"""// Module {i} of a generated compile_large project.

/// The namespace of module {i}.
enum {type_name(i)} {{
  /// The modulus that keeps every value small.
  private static let p = {P}

  /// A record that `makeItem` builds and `itemScore` reads.
  private struct Item {{
    let id: Int
    let size: Int
    let weight: Int
  }}

  /// A sum type that `makeShape` builds and `area` matches.
  private enum Shape {{
    case circle(Int)
    case rect(Int, Int)
    case tri(Int, Int, Int)
    case empty
  }}

  /// The first link of this module's chain, also called by the next module.
  static func base(_ x: Int) -> Int {{
    let a = x * {k[0]} + {k[1]}
    let b = a % p
    return (b * {k[2]} + {k[3]}) % p
  }}
"""
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
  /// Link {j} of the chain.
  private static func step{j}(_ x: Int) -> Int {{
    let y = {prev}(x)
    let a = y * {k[4 * j]} + x
    let b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % p
    if b % 2 == 0 {{
      return (a + b) % p
    }} else {{
      return (a + b * {k[4 * j + 3]}) % p
    }}
  }}
"""
        )
    out.append(
        f"""
  /// Builds an item from `x`.
  private static func makeItem(_ x: Int) -> Item {{
    Item(id: x % {k[56]}, size: x % 1000 + {k[57]}, weight: x * {k[58]} % p)
  }}

  /// Reads every field of `item`.
  private static func itemScore(_ item: Item) -> Int {{
    (item.id * {k[59]} + item.size * {k[60]} + item.weight) % p
  }}

  /// Picks a shape from `x`.
  private static func makeShape(_ x: Int) -> Shape {{
    switch x % 4 {{
    case 0: return .circle(x % {k[61]} + 1)
    case 1: return .rect(x % {k[62]} + 1, x % {k[63]} + 1)
    case 2: return .tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
    default: return .empty
    }}
  }}

  /// The area of `shape`, in whole units.
  private static func area(_ shape: Shape) -> Int {{
    switch shape {{
    case .circle(let r): return 3 * r * r
    case .rect(let w, let h): return w * h
    case .tri(let a, let b, let c): return a * b / 2 + c
    case .empty: return {k[67]}
    }}
  }}
"""
    )
    if i > 0:
        out.append(
            f"""
  /// Calls into the previous module.
  private static func link(_ x: Int) -> Int {{
    ({type_name(i - 1)}.base(x) + {k[68]}) % p
  }}
"""
        )
    else:
        out.append(
            f"""
  /// The first module has no previous module to call.
  private static func link(_ x: Int) -> Int {{
    (x + {k[68]}) % p
  }}
"""
        )
    out.append(
        """
  /// The function `main` calls.
  static func entry(_ x: Int) -> Int {
    let s = step13(x)
    let r = itemScore(makeItem(s))
    let h = area(makeShape(x))
    let l = link(x)
    return (s + r + h + l) % p
  }
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    one_line = ", ".join(f"{type_name(i)}.entry" for i in range(m))
    entries = f"let entries: [(Int) -> Int] = [{one_line}]\n"
    if len(entries) > 101:  # swift-format's 100 columns, plus the newline
        items = "".join(f"  {type_name(i)}.entry,\n" for i in range(m))
        entries = f"let entries: [(Int) -> Int] = [\n{items}]\n"
    return (
        "// Entry point of a generated compile_large project. It calls every module's `entry`\n"
        "// once, in order, and prints a checksum.\n"
        "\n"
        "/// The modulus that keeps every value small.\n"
        f"let p = {P}\n"
        "\n"
        f"{entries}"
        "let checksum = entries.reduce(0) { s, entry in (s * 31 + entry(s)) % p }\n"
        "print(checksum)\n"
    )


PACKAGE = """\
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "main",
  targets: [
    .executableTarget(name: "main")
  ]
)
"""


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    src = out / "Sources" / "main"
    src.mkdir(parents=True, exist_ok=True)
    (out / "Package.swift").write_text(PACKAGE)
    (src / "main.swift").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.swift").write_text(module(i))


if __name__ == "__main__":
    main()
