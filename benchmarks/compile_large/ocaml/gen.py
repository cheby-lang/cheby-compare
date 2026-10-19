"""Writes the OCaml project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one dune project in a single directory: dune-project, a dune
file declaring `(executable (name main))`, main.ml and one module per index,
m0000.ml to m<M-1>.ml. dune finds the modules and their dependency order with
ocamldep and compiles them in parallel. No .mli files: the SPEC says none is
needed. The output is in ocamlformat's default style and depends only on M.
"""

import sys
from pathlib import Path

P = 1000003


def c(i: int, s: int) -> int:
    """The constant of slot `s` in module `i`."""
    return (i * 7919 + s * 104729) % 10007 % 97 + 2


def name(i: int) -> str:
    return f"m{i:04d}"


def cap(i: int) -> str:
    """The OCaml module name of file mNNNN.ml."""
    return f"M{i:04d}"


def module(i: int) -> str:
    k = [c(i, s) for s in range(69)]
    out = [
        f"(* Module {i} of a generated compile_large project. *)\n",
        f"""
(* The modulus that keeps every value small. *)
let p = {P}

(* A record that make_item builds and item_score reads. *)
type item = {{ id : int; size : int; weight : int }}

(* A variant type that make_shape builds and area matches. *)
type shape = Circle of int | Rect of int * int | Tri of int * int * int | Empty

(* The first link of this module's chain, also called by the next module. *)
let base x =
  let a = (x * {k[0]}) + {k[1]} in
  let b = a mod p in
  ((b * {k[2]}) + {k[3]}) mod p
""",
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
(* Link {j} of the chain. *)
let step_{j} x =
  let y = {prev} x in
  let a = (y * {k[4 * j]}) + x in
  let b = ((a / {k[4 * j + 1]}) + {k[4 * j + 2]}) mod p in
  if b mod 2 = 0 then (a + b) mod p else (a + (b * {k[4 * j + 3]})) mod p
"""
        )
    out.append(
        f"""
(* Builds an item from x. *)
let make_item x =
  {{ id = x mod {k[56]}; size = (x mod 1000) + {k[57]}; weight = x * {k[58]} mod p }}

(* Reads every field of item. *)
let item_score item =
  ((item.id * {k[59]}) + (item.size * {k[60]}) + item.weight) mod p

(* Picks a shape from x. *)
let make_shape x =
  match x mod 4 with
  | 0 -> Circle ((x mod {k[61]}) + 1)
  | 1 -> Rect ((x mod {k[62]}) + 1, (x mod {k[63]}) + 1)
  | 2 -> Tri ((x mod {k[64]}) + 1, (x mod {k[65]}) + 1, (x mod {k[66]}) + 1)
  | _ -> Empty

(* The area of shape, in whole units. *)
let area shape =
  match shape with
  | Circle r -> 3 * r * r
  | Rect (w, h) -> w * h
  | Tri (a, b, c) -> (a * b / 2) + c
  | Empty -> {k[67]}
"""
    )
    if i > 0:
        out.append(
            f"""
(* Calls into the previous module. *)
let link x = ({cap(i - 1)}.base x + {k[68]}) mod p
"""
        )
    else:
        out.append(
            f"""
(* The first module has no previous module to call. *)
let link x = (x + {k[68]}) mod p
"""
        )
    out.append(
        """
(* The function main calls. *)
let entry x =
  let s = step_13 x in
  let r = item_score (make_item s) in
  let h = area (make_shape x) in
  let l = link x in
  (s + r + h + l) mod p
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    one_line = f"  let entries = [ {'; '.join(f'{cap(i)}.entry' for i in range(m))} ] in\n"
    if len(one_line) > 81:  # ocamlformat's 80 columns, plus the newline
        items = "".join(f"      {cap(i)}.entry;\n" for i in range(m))
        one_line = f"  let entries =\n    [\n{items}    ]\n  in\n"
    return (
        "(* Entry point of a generated compile_large project. *)\n"
        "(* It calls every module's entry once, in order, and prints a checksum. *)\n"
        "\n"
        "(* The modulus that keeps every value small. *)\n"
        f"let p = {P}\n"
        "\n"
        "let () =\n"
        f"{one_line}"
        "  let checksum =\n"
        "    List.fold_left (fun s entry -> ((s * 31) + entry s) mod p) 0 entries\n"
        "  in\n"
        '  Printf.printf "%d\\n" checksum\n'
    )


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    (out / "dune-project").write_text("(lang dune 3.0)\n")
    (out / "dune").write_text("(executable\n (name main))\n")
    (out / "main.ml").write_text(main_module(m))
    for i in range(m):
        (out / f"{name(i)}.ml").write_text(module(i))


if __name__ == "__main__":
    main()
