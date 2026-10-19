%% Two processes pass a number back and forth n times; prints n and the sum of the replies.
-module(main).
-export([main/0]).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    A = self(),
    B = spawn(fun() -> echo(N, A) end),
    Sum = play(1, N, B, 0),
    io:put_chars([integer_to_binary(N), $\n, integer_to_binary(Sum), $\n]).

%% Task B: answers each {ping, X} with {pong, X + 1}, exactly N times, then ends.
echo(0, _A) ->
    ok;
echo(N, A) ->
    receive
        {ping, X} ->
            A ! {pong, X + 1},
            echo(N - 1, A)
    end.

%% Task A: sends I = 1..N on ping and adds up the answers from pong.
play(I, N, _B, Sum) when I > N ->
    Sum;
play(I, N, B, Sum) ->
    B ! {ping, I},
    receive
        {pong, X} -> play(I + 1, N, B, Sum + X)
    end.
