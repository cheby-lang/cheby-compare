%% Prints a greeting and exits: the smallest program, for start-up time.
-module(main).
-export([main/0]).

main() ->
    io:format("Hello, world!~n").
