%% LRU cache: a capacity-bounded cache under a skewed pseudo-random key stream.
%%
%% Shape C of the spec: `entries` maps each key to {Value, Tick}, `by_tick` is a gb_trees from
%% each live tick to its key, and the smallest tick is the least recent entry.
-module(main).
-export([main/0]).

-define(MODULUS, 1000000007).
-define(LEHMER_M, 2147483647).
-define(LEHMER_A, 48271).
-define(SEED, 42).
-define(HOT_PERCENT, 80).
-define(KEY_SPACE_FACTOR, 16).

-record(lru, {capacity, entries = #{}, by_tick = gb_trees:empty(), clock = 0}).

main() ->
    [CapArg, OpsArg | _] = init:get_plain_arguments(),
    Capacity = list_to_integer(CapArg),
    Ops = list_to_integer(OpsArg),
    Hot = Capacity,
    Cold = Capacity * (?KEY_SPACE_FACTOR - 1),
    {Cache, Hits, Misses, Values} =
        run(Ops, ?SEED, Hot, Cold, #lru{capacity = Capacity}, 0, 0, 0),
    Checksum = checksum(gb_trees:next(gb_trees:iterator(Cache#lru.by_tick)), 1, 0),
    io:put_chars([
        <<"hits ">>, integer_to_binary(Hits), $\n,
        <<"misses ">>, integer_to_binary(Misses), $\n,
        <<"values ">>, integer_to_binary(Values), $\n,
        <<"checksum ">>, integer_to_binary(Checksum), $\n
    ]).

run(0, _State, _Hot, _Cold, Cache, Hits, Misses, Values) ->
    {Cache, Hits, Misses, Values};
run(N, State0, Hot, Cold, Cache, Hits, Misses, Values) ->
    State = State0 * ?LEHMER_A rem ?LEHMER_M,
    Key = pick_key(State, Hot, Cold),
    case get(Key, Cache) of
        {ok, Value, Cache1} ->
            run(N - 1, State, Hot, Cold, Cache1, Hits + 1, Misses,
                (Values + Value) rem ?MODULUS);
        miss ->
            run(N - 1, State, Hot, Cold, insert(Key, Key * 2 + 1, Cache), Hits, Misses + 1,
                Values)
    end.

pick_key(State, Hot, Cold) ->
    Draw = State div 100,
    case State rem 100 < ?HOT_PERCENT of
        true -> Draw rem Hot;
        false -> Hot + Draw rem Cold
    end.

%% A hit returns the value and makes the key the most recent.
get(Key, #lru{entries = Entries, by_tick = ByTick, clock = Clock} = Cache) ->
    case Entries of
        #{Key := {Value, Old}} ->
            ByTick1 = gb_trees:insert(Clock, Key, gb_trees:delete(Old, ByTick)),
            {ok, Value, Cache#lru{
                entries = Entries#{Key := {Value, Clock}},
                by_tick = ByTick1,
                clock = Clock + 1
            }};
        #{} ->
            miss
    end.

%% Inserts a key that is not present, evicting the least recent entry when full.
insert(Key, Value, #lru{capacity = Capacity, entries = Entries0, by_tick = ByTick0,
                        clock = Clock} = Cache) ->
    {Entries, ByTick} =
        case map_size(Entries0) =:= Capacity of
            true ->
                {_Tick, Oldest, ByTick1} = gb_trees:take_smallest(ByTick0),
                {maps:remove(Oldest, Entries0), ByTick1};
            false ->
                {Entries0, ByTick0}
        end,
    Cache#lru{
        entries = Entries#{Key => {Value, Clock}},
        by_tick = gb_trees:insert(Clock, Key, ByTick),
        clock = Clock + 1
    }.

checksum(none, _Position, Sum) ->
    Sum;
checksum({_Tick, Key, Iter}, Position, Sum) ->
    checksum(gb_trees:next(Iter), Position + 1, (Sum + Position * Key) rem ?MODULUS).
