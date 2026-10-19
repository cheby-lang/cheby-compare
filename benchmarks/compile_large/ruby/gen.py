"""Writes the Ruby project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is main.rb and one file per module, m0000.rb to m<M-1>.rb, side by
side. Each file defines `module M0000` with `Data.define` classes for Item and
the Shape variants, matched with `case`/`in`. main.rb loads the modules with
require_relative, in order. The output depends only on M.
"""

import sys
from pathlib import Path

P = 1000003


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def const(i: int) -> str:
    return f"M{i:04d}"


PRIVATE = (
    [f":step_{j}" for j in range(1, 14)]
    + [":make_item", ":item_score", ":make_shape", ":area", ":link"]
)


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = ["# frozen_string_literal: true\n\n"]
    out.append(f"# Module {i} of a generated compile_large project.\n\n")
    if i > 0:
        out.append(f'require_relative "{name(i - 1)}"\n\n')
    out.append(
        f"""# Twenty small functions, a record and a sum type; base and entry are public.
module {const(i)}
  # The modulus that keeps every value small.
  P = 1_000_003

  # A record that make_item builds and item_score reads.
  Item = Data.define(:id, :size, :weight)

  # The variants of Shape.
  Circle = Data.define(:r)
  Rect = Data.define(:w, :h)
  Tri = Data.define(:a, :b, :c)
  Empty = Data.define

  private_constant :Item, :Circle, :Rect, :Tri, :Empty

  # The first link of this module's chain, also called by the next module.
  def self.base(x)
    a = x * {k[0]} + {k[1]}
    b = a % P
    (b * {k[2]} + {k[3]}) % P
  end
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
  # Link {j} of the chain.
  def self.step_{j}(x)
    y = {prev}(x)
    a = y * {k[4 * j]} + x
    b = (a / {k[4 * j + 1]} + {k[4 * j + 2]}) % P
    if b.even?
      (a + b) % P
    else
      (a + b * {k[4 * j + 3]}) % P
    end
  end
"""
        )
    out.append(
        f"""
  # Builds an item from x.
  def self.make_item(x)
    Item.new(id: x % {k[56]}, size: x % 1000 + {k[57]}, weight: x * {k[58]} % P)
  end

  # Reads every field of item.
  def self.item_score(item)
    (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P
  end

  # Picks a shape from x.
  def self.make_shape(x)
    case x % 4
    when 0 then Circle.new(x % {k[61]} + 1)
    when 1 then Rect.new(x % {k[62]} + 1, x % {k[63]} + 1)
    when 2 then Tri.new(x % {k[64]} + 1, x % {k[65]} + 1, x % {k[66]} + 1)
    else Empty.new
    end
  end

  # The area of shape, in whole units.
  def self.area(shape)
    case shape
    in Circle[r] then 3 * r * r
    in Rect[w, h] then w * h
    in Tri[a, b, c] then a * b / 2 + c
    in Empty then {k[67]}
    end
  end
"""
    )
    if i > 0:
        out.append(
            f"""
  # Calls into the previous module.
  def self.link(x)
    ({const(i - 1)}.base(x) + {k[68]}) % P
  end
"""
        )
    else:
        out.append(
            f"""
  # The first module has no previous module to call.
  def self.link(x)
    (x + {k[68]}) % P
  end
"""
        )
    out.append(
        """
  # The function main calls.
  def self.entry(x)
    s = step_13(x)
    r = item_score(make_item(s))
    h = area(make_shape(x))
    l = link(x)
    (s + r + h + l) % P
  end

"""
    )
    out.append(f"  private_class_method {', '.join(PRIVATE)}\n")
    out.append("end\n")
    return "".join(out)


def main_module(m: int) -> str:
    requires = "".join(f'require_relative "{name(i)}"\n' for i in range(m))
    items = "".join(f"  {const(i)}.method(:entry),\n" for i in range(m))
    return (
        "# frozen_string_literal: true\n"
        "\n"
        "# Entry point of a generated compile_large project: it calls every module's entry once,\n"
        "# in order, and prints a checksum.\n"
        "\n"
        f"{requires}"
        "\n"
        "# The modulus that keeps every value small.\n"
        f"P = {P:_}\n"
        "\n"
        "ENTRIES = [\n"
        f"{items}"
        "].freeze\n"
        "\n"
        "s = ENTRIES.reduce(0) { |acc, entry| (acc * 31 + entry.call(acc)) % P }\n"
        "puts s\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "main.rb").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.rb").write_text(module(i))


if __name__ == "__main__":
    main()
