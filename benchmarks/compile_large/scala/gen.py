"""Writes the Scala project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is flat, in the default package: main.scala, whose top-level `@main def main()`
compiles to class `main` (langs/scala.toml runs `java ... main`), and one file per module,
M0000.scala to M<M-1>.scala, all compiled by one cold `scala-cli compile --server=false`. Each
module is an `object M0000` with a private `case class Item`, a private `enum Shape` with four
cases matched by `match`, and 20 methods. Only `base` and `entry` are public; everything else
is `private`. The output uses Scala 3's indentation syntax, two spaces, and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003
MAX_COLUMN = 100


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"M{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [
        f"""/** Module {i} of a generated compile_large project. */
object {name(i)}:
  /** The modulus that keeps every value small. */
  private val P = {P}L

  /** A record that `makeItem` builds and `itemScore` reads. */
  private case class Item(id: Long, size: Long, weight: Long)

  /** A sum type that `makeShape` builds and `area` matches. */
  private enum Shape:
    case Circle(r: Long)
    case Rect(w: Long, h: Long)
    case Tri(a: Long, b: Long, c: Long)
    case Empty

  /** The first link of this module's chain, also called by the next module. */
  def base(x: Long): Long =
    val a = x * {k[0]} + {k[1]}
    val b = a % P
    (b * {k[2]} + {k[3]}) % P
"""
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
  /** Link {j} of the chain. */
  private def step{j}(x: Long): Long =
    val y = {prev}(x)
    val a = y * {k[4 * j]} + x
    val b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P
    if b % 2 == 0 then (a + b) % P
    else (a + b * {k[4 * j + 3]}) % P
"""
        )
    out.append(
        f"""
  /** Builds an item from `x`. */
  private def makeItem(x: Long): Item =
    Item(id = x % {k[56]}, size = x % 1000 + {k[57]}, weight = x * {k[58]} % P)

  /** Reads every field of `item`. */
  private def itemScore(item: Item): Long =
    (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P

  /** Picks a shape from `x`. */
  private def makeShape(x: Long): Shape = x % 4 match
    case 0L => Shape.Circle(x % {k[61]} + 1)
    case 1L => Shape.Rect(x % {k[62]} + 1, x % {k[63]} + 1)
    case 2L => Shape.Tri(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
    case _  => Shape.Empty

  /** The area of `shape`, in whole units. */
  private def area(shape: Shape): Long = shape match
    case Shape.Circle(r)    => 3 * r * r
    case Shape.Rect(w, h)   => w * h
    case Shape.Tri(a, b, c) => a * b / 2 + c
    case Shape.Empty        => {k[67]}
"""
    )
    if i > 0:
        out.append(
            f"""
  /** Calls into the previous module. */
  private def link(x: Long): Long = ({name(i - 1)}.base(x) + {k[68]}) % P
"""
        )
    else:
        out.append(
            f"""
  /** The first module has no previous module to call. */
  private def link(x: Long): Long = (x + {k[68]}) % P
"""
        )
    out.append(
        """
  /** The function `main` calls. */
  def entry(x: Long): Long =
    val s = step13(x)
    val r = itemScore(makeItem(s))
    val h = area(makeShape(x))
    val l = link(x)
    (s + r + h + l) % P
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    one_line = ", ".join(f"{name(i)}.entry" for i in range(m))
    entries = f"  val entries: List[Long => Long] = List({one_line})\n"
    if len(entries) > MAX_COLUMN + 1:  # the column limit, plus the newline
        items = ",\n".join(f"    {name(i)}.entry" for i in range(m))
        entries = f"  val entries: List[Long => Long] = List(\n{items}\n  )\n"
    return (
        "// Entry point of a generated compile_large project. It calls every module's `entry`\n"
        "// once, in order, and prints a checksum.\n"
        "\n"
        "/** The modulus that keeps every value small. */\n"
        f"private val P = {P}L\n"
        "\n"
        "@main def main(): Unit =\n"
        f"{entries}"
        "  val s = entries.foldLeft(0L)((acc, entry) => (acc * 31 + entry(acc)) % P)\n"
        "  println(s)\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if not 1 <= m <= 9999:
        sys.exit("M must be between 1 and 9999")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.scala").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.scala").write_text(module(i))


if __name__ == "__main__":
    main()
