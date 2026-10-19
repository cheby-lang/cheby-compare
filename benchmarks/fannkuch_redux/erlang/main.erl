%% Fannkuch-redux: counts pancake flips over every permutation of 0..n-1, as lists.
-module(main).
-export([main/0]).

main() ->
    [Arg | _] = init:get_plain_arguments(),
    N = list_to_integer(Arg),
    {Checksum, MaxFlips} = fannkuch(max(N, 1)),
    io:put_chars([integer_to_binary(Checksum), "\nPfannkuchen(", integer_to_binary(N), ") = ",
                  integer_to_binary(MaxFlips), "\n"]).

fannkuch(N) ->
    Perm1 = lists:seq(0, N - 1),
    Count = erlang:make_tuple(N, 0),
    loop(Perm1, Count, N, N, 0, 0, 0).

%% Count is a tuple indexed from 0 as element(I + 1, Count).
loop(Perm1, Count0, R0, N, MaxFlips0, Checksum0, PermIndex) ->
    Count = reset(R0, Count0),
    Flips = flips(Perm1, 0),
    MaxFlips = max(MaxFlips0, Flips),
    Checksum = case PermIndex rem 2 of
                   0 -> Checksum0 + Flips;
                   1 -> Checksum0 - Flips
               end,
    next(Perm1, Count, 1, N, MaxFlips, Checksum, PermIndex).

%% Step 1: count[r - 1] = r while r != 1.
reset(1, Count) -> Count;
reset(R, Count) -> reset(R - 1, setelement(R, Count, R)).

%% Step 2: flip the first k + 1 elements until 0 is in front.
flips([0 | _], Flips) -> Flips;
flips([K | _] = Perm, Flips) ->
    {Front, Back} = lists:split(K + 1, Perm),
    flips(lists:reverse(Front, Back), Flips + 1).

%% Step 3: rotate the first r + 1 elements left by one and step the counters.
next(_Perm1, _Count, N, N, MaxFlips, Checksum, _PermIndex) ->
    {Checksum, MaxFlips};
next(Perm1, Count, R, N, MaxFlips, Checksum, PermIndex) ->
    {[First | Rest], Back} = lists:split(R + 1, Perm1),
    Rotated = Rest ++ [First | Back],
    C = element(R + 1, Count) - 1,
    Count1 = setelement(R + 1, Count, C),
    case C > 0 of
        true -> loop(Rotated, Count1, R, N, MaxFlips, Checksum, PermIndex + 1);
        false -> next(Rotated, Count1, R + 1, N, MaxFlips, Checksum, PermIndex)
    end.
