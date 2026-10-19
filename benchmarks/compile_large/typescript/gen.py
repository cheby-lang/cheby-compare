"""Writes the TypeScript project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is a small Node project: package.json ({"type": "module"}),
tsconfig.json (ES2024, NodeNext, strict), main.ts and one ES module per
index, m0000.ts to m<M-1>.ts, side by side. The output is in Prettier form
and depends only on M.

tsconfig.json loads the shared @types/node through typeRoots, like every other
TypeScript implementation (hello_world included), so the compile-speed
numbers share one baseline of declaration input. The modules use no Node API
themselves. The typeRoots path is relative from <outdir> to the repository's
build/typescript/node_modules/@types, which setup/typescript.sh creates.
"""

import json
import os
import sys
from pathlib import Path

P = 1000003
WIDTH = 80  # Prettier's printWidth


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def ret_object(indent: str, fields: list[str]) -> str:
    """A `return { ... };` statement, on one line when it fits, as Prettier breaks it."""
    one = f"{indent}return {{ {', '.join(fields)} }};\n"
    if len(one) - 1 <= WIDTH:
        return one
    inner = "".join(f"{indent}  {f},\n" for f in fields)
    return f"{indent}return {{\n{inner}{indent}}};\n"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [f"// Module {i} of a generated compile_large project.\n"]
    if i > 0:
        out.append(f'\nimport * as {name(i - 1)} from "./{name(i - 1)}.js";\n')
    out.append(
        f"""
/** The modulus that keeps every value small. */
const P = {P};

/** A record that `makeItem` builds and `itemScore` reads. */
interface Item {{
  id: number;
  size: number;
  weight: number;
}}

/** A sum type that `makeShape` builds and `area` matches. */
type Shape =
  | {{ kind: "circle"; r: number }}
  | {{ kind: "rect"; w: number; h: number }}
  | {{ kind: "tri"; a: number; b: number; c: number }}
  | {{ kind: "empty" }};

/** The first link of this module's chain, also called by the next module. */
export function base(x: number): number {{
  const a = x * {k[0]} + {k[1]};
  const b = a % P;
  return (b * {k[2]} + {k[3]}) % P;
}}
"""
    )
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step{j - 1}"
        out.append(
            f"""
/** Link {j} of the chain. */
function step{j}(x: number): number {{
  const y = {prev}(x);
  const a = y * {k[4 * j]} + x;
  const b = (Math.trunc(a / {k[4 * j + 1]}) + {k[4 * j + 2]}) % P;
  if (b % 2 === 0) {{
    return (a + b) % P;
  }} else {{
    return (a + b * {k[4 * j + 3]}) % P;
  }}
}}
"""
        )
    item = ret_object(
        "  ",
        [f"id: x % {k[56]}", f"size: (x % 1000) + {k[57]}", f"weight: (x * {k[58]}) % P"],
    )
    circle = ret_object("      ", ['kind: "circle"', f"r: (x % {k[61]}) + 1"])
    rect = ret_object(
        "      ", ['kind: "rect"', f"w: (x % {k[62]}) + 1", f"h: (x % {k[63]}) + 1"]
    )
    tri = ret_object(
        "      ",
        [
            'kind: "tri"',
            f"a: (x % {k[64]}) + 1",
            f"b: (x % {k[65]}) + 1",
            f"c: (x % {k[66]}) + 1",
        ],
    )
    out.append(
        f"""
/** Builds an item from `x`. */
function makeItem(x: number): Item {{
{item}}}

/** Reads every field of `item`. */
function itemScore(item: Item): number {{
  return (item.id * {k[59]} + item.size * {k[60]} + item.weight) % P;
}}

/** Picks a shape from `x`. */
function makeShape(x: number): Shape {{
  switch (x % 4) {{
    case 0:
{circle}    case 1:
{rect}    case 2:
{tri}    default:
      return {{ kind: "empty" }};
  }}
}}

/** The area of `shape`, in whole units. */
function area(shape: Shape): number {{
  switch (shape.kind) {{
    case "circle":
      return 3 * shape.r * shape.r;
    case "rect":
      return shape.w * shape.h;
    case "tri":
      return Math.trunc((shape.a * shape.b) / 2) + shape.c;
    case "empty":
      return {k[67]};
  }}
}}
"""
    )
    if i > 0:
        out.append(
            f"""
/** Calls into the previous module. */
function link(x: number): number {{
  return ({name(i - 1)}.base(x) + {k[68]}) % P;
}}
"""
        )
    else:
        out.append(
            f"""
/** The first module has no previous module to call. */
function link(x: number): number {{
  return (x + {k[68]}) % P;
}}
"""
        )
    out.append(
        """
/** The function `main` calls. */
export function entry(x: number): number {
  const s = step13(x);
  const r = itemScore(makeItem(s));
  const h = area(makeShape(x));
  const l = link(x);
  return (s + r + h + l) % P;
}
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    imports = "".join(f'import * as {name(i)} from "./{name(i)}.js";\n' for i in range(m))
    head = "const entries: Array<(x: number) => number> = ["
    one_line = f"{head}{', '.join(f'{name(i)}.entry' for i in range(m))}];\n"
    if len(one_line) - 1 <= WIDTH:
        entries = one_line
    else:
        items = "".join(f"  {name(i)}.entry,\n" for i in range(m))
        entries = f"{head}\n{items}];\n"
    return (
        "// Entry point of a generated compile_large project. It calls every\n"
        "// module's `entry` once, in order, and prints a checksum.\n"
        "\n"
        f"{imports}"
        "\n"
        "/** The modulus that keeps every value small. */\n"
        f"const P = {P};\n"
        "\n"
        f"{entries}"
        "\n"
        "const checksum = entries.reduce((s, entry) => (s * 31 + entry(s)) % P, 0);\n"
        "console.log(checksum);\n"
    )


PACKAGE_JSON = """{
  "private": true,
  "type": "module"
}
"""

# The repository root: benchmarks/compile_large/typescript/gen.py is three levels down.
ROOT = Path(__file__).resolve().parents[3]
TYPE_ROOTS = ROOT / "build" / "typescript" / "node_modules" / "@types"


def tsconfig_json(out: Path) -> str:
    type_roots = Path(os.path.relpath(TYPE_ROOTS, out.resolve())).as_posix()
    return f"""{{
  "compilerOptions": {{
    "target": "es2024",
    "module": "nodenext",
    "strict": true,
    "skipLibCheck": true,
    "rootDir": ".",
    "types": ["node"],
    "typeRoots": [{json.dumps(type_roots)}]
  }},
  "include": ["*.ts"]
}}
"""


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "package.json").write_text(PACKAGE_JSON)
    (out / "tsconfig.json").write_text(tsconfig_json(out))
    (out / "main.ts").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.ts").write_text(module(i))


if __name__ == "__main__":
    main()
