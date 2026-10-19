%% Binary trees: builds and checks many perfect trees of {node, L, R} tuples.
-module(main).
%% make/2 is exported only so that each leaf is a fresh heap tuple. A leaf written as
%% {node, nil, nil}, or built from a nil passed between local functions, is folded by the
%% compiler into one shared literal, and the SPEC requires one allocation per node.
-export([main/0, make/2]).

-define(MIN_DEPTH, 4).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    Stretch = N + 1,
    io:put_chars(["stretch tree of depth ", integer_to_binary(Stretch), "\t check: ",
                  integer_to_binary(check(make(Stretch, nil))), "\n"]),
    LongLived = make(N, nil),
    depths(?MIN_DEPTH, N),
    io:put_chars(["long lived tree of depth ", integer_to_binary(N), "\t check: ",
                  integer_to_binary(check(LongLived)), "\n"]).

make(0, Empty) -> {node, Empty, Empty};
make(D, Empty) ->
    L = make(D - 1, Empty),
    R = make(D - 1, Empty),
    {node, L, R}.

check(nil) -> 0;
check({node, L, R}) -> 1 + check(L) + check(R).

depths(D, N) when D > N -> ok;
depths(D, N) ->
    Iterations = 1 bsl (N - D + ?MIN_DEPTH),
    Total = repeat(Iterations, D, 0),
    io:put_chars([integer_to_binary(Iterations), "\t trees of depth ", integer_to_binary(D),
                  "\t check: ", integer_to_binary(Total), "\n"]),
    depths(D + 2, N).

repeat(0, _D, Total) -> Total;
repeat(I, D, Total) -> repeat(I - 1, D, Total + check(make(D, nil))).
