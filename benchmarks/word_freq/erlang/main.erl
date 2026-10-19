%% word_freq: counts the words of a file and prints the 20 most frequent.
-module(main).
-export([main/0]).

-define(TOP, 20).

main() ->
    [Path | _] = init:get_plain_arguments(),
    {ok, Text} = file:read_file(Path),
    Words = binary:split(Text, [<<" ">>, <<"\n">>], [global, trim_all]),
    Counts = lists:foldl(
        fun(Word, Acc) -> maps:update_with(Word, fun(C) -> C + 1 end, 1, Acc) end,
        #{},
        Words
    ),
    Total = length(Words),
    Ranked = lists:sort(
        fun({W1, C1}, {W2, C2}) -> C1 > C2 orelse (C1 =:= C2 andalso W1 =< W2) end,
        maps:to_list(Counts)
    ),
    Top = lists:sublist(Ranked, ?TOP),
    io:put_chars([
        <<"total ">>, integer_to_binary(Total), $\n,
        <<"distinct ">>, integer_to_binary(map_size(Counts)), $\n,
        [[integer_to_binary(C), $\s, W, $\n] || {W, C} <- Top]
    ]).
