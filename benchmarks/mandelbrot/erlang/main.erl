%% Mandelbrot: escape-time iteration on an N x N grid, printing counts and a checksum.
-module(main).
-export([main/0]).

-define(MAX_ITER, 50).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    {Inside, Iterations, Checksum} = rows(0, N, float(N), 0, 0, 0),
    io:put_chars(["inside ", integer_to_binary(Inside), "\n",
                  "iterations ", integer_to_binary(Iterations), "\n",
                  "checksum ", integer_to_binary(Checksum rem (1 bsl 32)), "\n"]).

rows(N, N, _FN, Inside, Iters, Sum) -> {Inside, Iters, Sum};
rows(Y, N, FN, Inside, Iters, Sum) ->
    Ci = 2.0 * float(Y) / FN - 1.0,
    {Inside1, Iters1, Sum1} = cols(0, Y, N, FN, Ci, Inside, Iters, Sum),
    rows(Y + 1, N, FN, Inside1, Iters1, Sum1).

cols(N, _Y, N, _FN, _Ci, Inside, Iters, Sum) -> {Inside, Iters, Sum};
cols(X, Y, N, FN, Ci, Inside, Iters, Sum) ->
    Cr = 2.0 * float(X) / FN - 1.5,
    case escape(0.0, 0.0, Cr, Ci, 0) of
        ?MAX_ITER ->
            cols(X + 1, Y, N, FN, Ci, Inside + 1, Iters + ?MAX_ITER, Sum + (Y * N + X));
        I ->
            cols(X + 1, Y, N, FN, Ci, Inside, Iters + I, Sum)
    end.

escape(_Zr, _Zi, _Cr, _Ci, ?MAX_ITER) -> ?MAX_ITER;
escape(Zr, Zi, Cr, Ci, I) ->
    Zr2 = Zr * Zr,
    Zi2 = Zi * Zi,
    case Zr2 + Zi2 > 4.0 of
        true -> I;
        false -> escape(Zr2 - Zi2 + Cr, 2.0 * Zr * Zi + Ci, Cr, Ci, I + 1)
    end.
