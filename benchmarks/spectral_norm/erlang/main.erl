%% Spectral norm: 10 rounds of the power method on A^T A, with vectors as lists of floats.
-module(main).
-export([main/0]).
-compile({inline, [a/2]}).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    Indices = lists:seq(0, N - 1),
    U0 = lists:duplicate(N, 1.0),
    {U, V} = rounds(10, U0, U0, Indices),
    {VBv, VV} = dots(U, V, 0.0, 0.0),
    Result = case VV == 0.0 of
                 true -> 0;
                 false -> round(math:sqrt(VBv / VV) * 1.0e9)
             end,
    io:put_chars([integer_to_binary(Result), "\n"]).

rounds(0, U, V, _Indices) -> {U, V};
rounds(K, U, _V, Indices) ->
    V = times_ata(U, Indices),
    U1 = times_ata(V, Indices),
    rounds(K - 1, U1, V, Indices).

times_ata(X, Indices) -> times_at(times_a(X, Indices), Indices).

times_a(X, Indices) -> [row_sum(I, X, 0, 0.0) || I <- Indices].

times_at(X, Indices) -> [col_sum(I, X, 0, 0.0) || I <- Indices].

row_sum(_I, [], _J, S) -> S;
row_sum(I, [Xj | Xs], J, S) -> row_sum(I, Xs, J + 1, S + a(I, J) * Xj).

col_sum(_I, [], _J, S) -> S;
col_sum(I, [Xj | Xs], J, S) -> col_sum(I, Xs, J + 1, S + a(J, I) * Xj).

a(I, J) -> 1.0 / ((I + J) * (I + J + 1) div 2 + I + 1).

dots([], [], VBv, VV) -> {VBv, VV};
dots([Ui | Us], [Vi | Vs], VBv, VV) -> dots(Us, Vs, VBv + Ui * Vi, VV + Vi * Vi).
