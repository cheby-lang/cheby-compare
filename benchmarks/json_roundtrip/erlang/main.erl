%% json_roundtrip: parses a JSON array of records, transforms it and serializes it again.
-module(main).
-export([main/0]).

-define(FNV_OFFSET, 2166136261).
-define(FNV_PRIME, 16777619).

-record(stats, {
    records = 0,
    active = 0,
    score_sum = 0,
    tags = 0,
    history = 0,
    amount_sum = 0,
    output_bytes = 0,
    hash = ?FNV_OFFSET
}).

main() ->
    [Path, RepsArg | _] = init:get_plain_arguments(),
    Reps = list_to_integer(RepsArg),
    {ok, Text} = file:read_file(Path),
    S = repeat(Text, 0, Reps, #stats{}),
    io:put_chars([
        line(<<"records">>, S#stats.records),
        line(<<"active">>, S#stats.active),
        line(<<"score_sum">>, S#stats.score_sum),
        line(<<"tags">>, S#stats.tags),
        line(<<"history">>, S#stats.history),
        line(<<"amount_sum">>, S#stats.amount_sum),
        line(<<"output_bytes">>, S#stats.output_bytes),
        line(<<"output_fnv1a">>, S#stats.hash)
    ]).

line(Name, Value) -> [Name, $\s, integer_to_binary(Value), $\n].

repeat(_Text, Reps, Reps, S) ->
    S;
repeat(Text, Rep, Reps, S0) ->
    Records = json:decode(Text),
    {S1, KeptRev} = lists:foldl(fun visit/2, {S0, []}, Records),
    Out = iolist_to_binary(json:encode(lists:reverse(KeptRev), fun encoder/2)),
    S2 = S1#stats{output_bytes = S1#stats.output_bytes + byte_size(Out)},
    S3 =
        case Rep =:= Reps - 1 of
            true -> S2#stats{hash = fnv1a(?FNV_OFFSET, Out)};
            false -> S2
        end,
    repeat(Text, Rep + 1, Reps, S3).

visit(
    #{
        <<"id">> := Id,
        <<"name">> := Name,
        <<"active">> := Active,
        <<"score">> := Score,
        <<"tags">> := Tags,
        <<"address">> := Address,
        <<"history">> := History
    },
    {S, Kept}
) ->
    Total = lists:foldl(fun(#{<<"amount">> := A}, Sum) -> Sum + A end, 0, History),
    NTags = length(Tags),
    S1 = S#stats{
        records = S#stats.records + 1,
        score_sum = S#stats.score_sum + Score,
        tags = S#stats.tags + NTags,
        history = S#stats.history + length(History),
        amount_sum = S#stats.amount_sum + Total
    },
    case Active of
        true ->
            Out = [
                {<<"id">>, Id},
                {<<"name">>, Name},
                {<<"score">>, Score + 100 * NTags},
                {<<"tags">>, Tags},
                {<<"address">>, address(Address)},
                {<<"history">>, [entry(E) || E <- History]},
                {<<"total">>, Total}
            ],
            {S1#stats{active = S1#stats.active + 1}, [Out | Kept]};
        false ->
            {S1, Kept}
    end.

%% json:decode/1 gives maps, which encode in sorted key order; rebuild them as ordered
%% key-value lists.
address(#{<<"street">> := Street, <<"city">> := City, <<"zip">> := Zip}) ->
    [{<<"street">>, Street}, {<<"city">>, City}, {<<"zip">>, Zip}].

entry(#{<<"day">> := Day, <<"amount">> := Amount}) ->
    [{<<"day">>, Day}, {<<"amount">>, Amount}].

%% Encodes a key-value list (a proplist) as an object, keeping its order.
encoder([{_, _} | _] = KVs, Encode) -> json:encode_key_value_list(KVs, Encode);
encoder(Other, Encode) -> json:encode_value(Other, Encode).

fnv1a(H, <<B, Rest/binary>>) -> fnv1a(((H bxor B) * ?FNV_PRIME) band 16#FFFFFFFF, Rest);
fnv1a(H, <<>>) -> H.
