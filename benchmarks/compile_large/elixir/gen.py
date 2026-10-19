"""Writes the Elixir project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one Mix project whose app is `main`, the layout every Elixir
benchmark uses (langs/elixir.md): mix.exs, lib/main.ex (Main.main/0, the
entry) and one module per index, lib/m0000.ex to lib/m<M-1>.ex. Each module
has a nested struct module for Item and tagged tuples for Shape. `mix compile`
compiles the modules in parallel. The output is in `mix format` style and
depends only on M.
"""

import sys
from pathlib import Path

P = 1000003

MIX_EXS = """defmodule Main.MixProject do
  use Mix.Project

  def project do
    [
      app: :main,
      version: "1.0.0",
      elixir: "~> 1.20",
      deps: []
    ]
  end
end
"""


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    """The Elixir module name of module `i`."""
    return f"M{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [
        f'''# Module {i} of a generated compile_large project.
defmodule {name(i)} do
  # The modulus that keeps every value small.
  @p 1_000_003

  # A record that make_item builds and item_score reads.
  defmodule Item do
    defstruct [:id, :size, :weight]
  end

  # Shape, a sum type that make_shape builds and area matches, is a tagged tuple:
  # {{:circle, r}} | {{:rect, w, h}} | {{:tri, a, b, c}} | :empty

  # The first link of this module's chain, also called by the next module.
  def base(x) do
    a = x * {k[0]} + {k[1]}
    b = rem(a, @p)
    rem(b * {k[2]} + {k[3]}, @p)
  end
'''
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
  # Link {j} of the chain.
  defp step_{j}(x) do
    y = {prev}(x)
    a = y * {k[4 * j]} + x
    b = rem(div(a, {k[4 * j + 1]}) + {k[4 * j + 2]}, @p)

    if rem(b, 2) == 0 do
      rem(a + b, @p)
    else
      rem(a + b * {k[4 * j + 3]}, @p)
    end
  end
"""
        )
    out.append(
        f"""
  # Builds an item from x.
  defp make_item(x) do
    %Item{{id: rem(x, {k[56]}), size: rem(x, 1000) + {k[57]}, weight: rem(x * {k[58]}, @p)}}
  end

  # Reads every field of the item.
  defp item_score(%Item{{id: id, size: size, weight: weight}}) do
    rem(id * {k[59]} + size * {k[60]} + weight, @p)
  end

  # Picks a shape from x.
  defp make_shape(x) do
    case rem(x, 4) do
      0 -> {{:circle, rem(x, {k[61]}) + 1}}
      1 -> {{:rect, rem(x, {k[62]}) + 1, rem(x, {k[63]}) + 1}}
      2 -> {{:tri, rem(x, {k[64]}) + 1, rem(x, {k[65]}) + 1, rem(x, {k[66]}) + 1}}
      3 -> :empty
    end
  end

  # The area of the shape, in whole units.
  defp area({{:circle, r}}), do: 3 * r * r
  defp area({{:rect, w, h}}), do: w * h
  defp area({{:tri, a, b, c}}), do: div(a * b, 2) + c
  defp area(:empty), do: {k[67]}
"""
    )
    if i > 0:
        out.append(
            f"""
  # Calls into the previous module.
  defp link(x) do
    rem({name(i - 1)}.base(x) + {k[68]}, @p)
  end
"""
        )
    else:
        out.append(
            f"""
  # The first module has no previous module to call.
  defp link(x) do
    rem(x + {k[68]}, @p)
  end
"""
        )
    out.append(
        """
  # The function main calls.
  def entry(x) do
    s = step_13(x)
    r = item_score(make_item(s))
    h = area(make_shape(x))
    l = link(x)
    rem(s + r + h + l, @p)
  end
end
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    refs = [f"&{name(i)}.entry/1" for i in range(m)]
    entries = f"    entries = [{', '.join(refs)}]\n"
    if len(entries) > 99:  # mix format's 98 columns, plus the newline
        items = ",\n".join(f"      {r}" for r in refs)
        entries = f"    entries = [\n{items}\n    ]\n\n"
    return (
        "# Entry point of a generated compile_large project. It calls every module's entry\n"
        "# once, in order, and prints a checksum.\n"
        "defmodule Main do\n"
        "  # The modulus that keeps every value small.\n"
        "  @p 1_000_003\n"
        "\n"
        "  def main do\n"
        f"{entries}"
        "    checksum = Enum.reduce(entries, 0, fn entry, s -> rem(s * 31 + entry.(s), @p) end)\n"
        "    IO.puts(Integer.to_string(checksum))\n"
        "  end\n"
        "end\n"
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    lib = out / "lib"
    lib.mkdir(parents=True, exist_ok=True)
    (out / "mix.exs").write_text(MIX_EXS)
    (lib / "main.ex").write_text(main_module(m))
    for i in range(m):
        (lib / f"{name(i).lower()}.ex").write_text(module(i))


if __name__ == "__main__":
    main()
