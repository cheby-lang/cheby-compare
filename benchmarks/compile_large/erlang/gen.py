"""Writes the Erlang project of the compile_large benchmark (see ../SPEC.md).

Usage: python3 gen.py <M> <outdir>

The project is one rebar3 application named `main`: rebar.config,
src/main.app.src, src/main.erl (the entry, main/0) and one module per index,
src/m0000.erl to src/m<M-1>.erl. `rebar3 compile` builds the independent
modules in parallel. The output is in erlfmt style and depends only on M.
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
    out = [
        f"""%% Module {i} of a generated compile_large project.
-module({name(i)}).
-compile({{no_auto_import, [link/1]}}).
-export([base/1, entry/1]).

%% The modulus that keeps every value small.
-define(P, {P}).

%% A record that make_item builds and item_score reads.
-record(item, {{id :: integer(), size :: integer(), weight :: integer()}}).

%% A sum type that make_shape builds and area matches.
-type shape() ::
    {{circle, integer()}}
    | {{rect, integer(), integer()}}
    | {{tri, integer(), integer(), integer()}}
    | empty.

%% The first link of this module's chain, also called by the next module.
-spec base(integer()) -> integer().
base(X) ->
    A = X * {k[0]} + {k[1]},
    B = A rem ?P,
    (B * {k[2]} + {k[3]}) rem ?P.
"""
    ]
    for j in range(1, 14):
        prev = "base" if j == 1 else f"step_{j - 1}"
        out.append(
            f"""
%% Link {j} of the chain.
-spec step_{j}(integer()) -> integer().
step_{j}(X) ->
    Y = {prev}(X),
    A = Y * {k[4 * j]} + X,
    B = (A div {k[4 * j + 1]} + {k[4 * j + 2]}) rem ?P,
    case B rem 2 of
        0 -> (A + B) rem ?P;
        _ -> (A + B * {k[4 * j + 3]}) rem ?P
    end.
"""
        )
    out.append(
        f"""
%% Builds an item from X.
-spec make_item(integer()) -> #item{{}}.
make_item(X) ->
    #item{{id = X rem {k[56]}, size = X rem 1000 + {k[57]}, weight = X * {k[58]} rem ?P}}.

%% Reads every field of the item.
-spec item_score(#item{{}}) -> integer().
item_score(#item{{id = Id, size = Size, weight = Weight}}) ->
    (Id * {k[59]} + Size * {k[60]} + Weight) rem ?P.

%% Picks a shape from X.
-spec make_shape(integer()) -> shape().
make_shape(X) ->
    case X rem 4 of
        0 -> {{circle, X rem {k[61]} + 1}};
        1 -> {{rect, X rem {k[62]} + 1, X rem {k[63]} + 1}};
        2 -> {{tri, X rem {k[64]} + 1, X rem {k[65]} + 1, X rem {k[66]} + 1}};
        3 -> empty
    end.

%% The area of the shape, in whole units.
-spec area(shape()) -> integer().
area({{circle, R}}) -> 3 * R * R;
area({{rect, W, H}}) -> W * H;
area({{tri, A, B, C}}) -> (A * B) div 2 + C;
area(empty) -> {k[67]}.
"""
    )
    if i > 0:
        out.append(
            f"""
%% Calls into the previous module.
-spec link(integer()) -> integer().
link(X) ->
    ({name(i - 1)}:base(X) + {k[68]}) rem ?P.
"""
        )
    else:
        out.append(
            f"""
%% The first module has no previous module to call.
-spec link(integer()) -> integer().
link(X) ->
    (X + {k[68]}) rem ?P.
"""
        )
    out.append(
        """
%% The function main calls.
-spec entry(integer()) -> integer().
entry(X) ->
    S = step_13(X),
    R = item_score(make_item(S)),
    H = area(make_shape(X)),
    L = link(X),
    (S + R + H + L) rem ?P.
"""
    )
    return "".join(out)


def main_module(m: int) -> str:
    funs = [f"fun {name(i)}:entry/1" for i in range(m)]
    entries = f"    Entries = [{', '.join(funs)}],\n"
    if len(entries) > 101:  # erlfmt's 100 columns, plus the newline
        items = ",\n".join(f"        {f}" for f in funs)
        entries = f"    Entries = [\n{items}\n    ],\n"
    return (
        "%% Entry point of a generated compile_large project. It calls every\n"
        "%% module's entry once, in order, and prints a checksum.\n"
        "-module(main).\n"
        "-export([main/0]).\n"
        "\n"
        "%% The modulus that keeps every value small.\n"
        f"-define(P, {P}).\n"
        "\n"
        "main() ->\n"
        f"{entries}"
        "    Checksum = lists:foldl(fun(Entry, S) -> (S * 31 + Entry(S)) rem ?P end, 0, Entries),\n"
        "    io:put_chars([integer_to_binary(Checksum), $\\n]).\n"
    )


APP_SRC = """{application, main, [
    {description, "A generated compile_large project"},
    {vsn, "0.1.0"},
    {registered, []},
    {applications, [kernel, stdlib]},
    {env, []},
    {modules, []}
]}.
"""


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: python3 gen.py <M> <outdir>")
    m = int(sys.argv[1])
    if m < 1:
        sys.exit("M must be at least 1")
    out = Path(sys.argv[2])
    src = out / "src"
    src.mkdir(parents=True, exist_ok=True)
    (out / "rebar.config").write_text("{erl_opts, [deterministic, no_debug_info]}.\n")
    (src / "main.app.src").write_text(APP_SRC)
    (src / "main.erl").write_text(main_module(m))
    for i in range(m):
        (src / f"{name(i)}.erl").write_text(module(i))


if __name__ == "__main__":
    main()
