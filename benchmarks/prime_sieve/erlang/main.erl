%% The concurrent prime sieve: a generator process and one filter process per prime,
%% connected by the pull protocol (each stage asks the one before it for every number).
-module(main).
-export([main/0]).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    Gen = spawn(fun() -> generator(2) end),
    {Last, Sum} = primes(N, Gen, self(), 0, 0),
    %% The stages stay blocked in receive; the halt(0) after main ends them (SPEC "Shut down",
    %% option 1).
    io:put_chars(["primes: ", integer_to_binary(N),
                  "\nlast: ", integer_to_binary(Last),
                  "\nsum: ", integer_to_binary(Sum), $\n]).

%% Receives N primes from the end of the pipeline, spawning a filter after each one.
%% Self is the main process's pid, set up once.
primes(0, _Cur, _Self, Last, Sum) ->
    {Last, Sum};
primes(K, Cur, Self, _Last, Sum) ->
    Cur ! {next, Self},
    receive
        {num, P} ->
            Next = spawn(fun() -> filter(P, Cur) end),
            primes(K - 1, Next, Self, P, Sum + P)
    end.

%% Answers each request with the next integer, from 2 upward.
generator(I) ->
    receive
        {next, From} ->
            From ! {num, I},
            generator(I + 1)
    end.

%% Answers each request with the next number from Up that Prime does not divide.
%% Self is this filter's own pid, set up once, so requests upstream carry it.
filter(Prime, Up) ->
    filter_loop(Prime, Up, self()).

filter_loop(Prime, Up, Self) ->
    receive
        {next, From} ->
            From ! {num, pull(Prime, Up, Self)},
            filter_loop(Prime, Up, Self)
    end.

pull(Prime, Up, Self) ->
    Up ! {next, Self},
    receive
        {num, M} when M rem Prime =:= 0 -> pull(Prime, Up, Self);
        {num, M} -> M
    end.
