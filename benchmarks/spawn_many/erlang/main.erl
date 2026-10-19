%% Spawns n short processes in batches of 1000, joins each batch, prints the sum of their results.
-module(main).
-export([main/0]).

-define(BATCH, 1000).
-define(ROUNDS, 10).
-define(MODULUS, 2147483647).
-define(MULTIPLIER, 48271).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    Sum = batches(0, N, 0),
    io:put_chars(["tasks: ", integer_to_binary(N), "\nsum: ", integer_to_binary(Sum), $\n]).

%% The value of the task with this index: ROUNDS MINSTD steps from Index + 1.
work(Index) ->
    steps(?ROUNDS, Index + 1).

steps(0, X) -> X;
steps(K, X) -> steps(K - 1, X * ?MULTIPLIER rem ?MODULUS).

batches(Start, N, Sum) when Start >= N ->
    Sum;
batches(Start, N, Sum) ->
    Batch = spawn_and_join(Start, min(?BATCH, N - Start)),
    batches(Start + ?BATCH, N, Sum + Batch).

%% Spawns one process per index in Start..Start + Count - 1, then receives every result,
%% tagged with this batch's fresh reference.
spawn_and_join(Start, Count) ->
    Parent = self(),
    Ref = make_ref(),
    spawn_all(Start, Start + Count, Parent, Ref),
    join(Count, Ref, 0).

spawn_all(I, End, _Parent, _Ref) when I >= End ->
    ok;
spawn_all(I, End, Parent, Ref) ->
    spawn(fun() -> Parent ! {Ref, work(I)} end),
    spawn_all(I + 1, End, Parent, Ref).

join(0, _Ref, Sum) ->
    Sum;
join(K, Ref, Sum) ->
    receive
        {Ref, V} -> join(K - 1, Ref, Sum + V)
    end.
