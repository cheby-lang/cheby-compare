%% N-body: the Sun and four giant planets, advanced in fixed steps; prints the energy before and after.
-module(main).
-export([main/0]).

-define(PI, 3.141592653589793).
-define(SOLAR_MASS, (4.0 * ?PI * ?PI)).
-define(DAYS_PER_YEAR, 365.24).
-define(DT, 0.01).

%% A body is {X, Y, Z, Vx, Vy, Vz, Mass}; the system is a list of five bodies.

main() ->
    [Arg | _] = init:get_plain_arguments(),
    Steps = list_to_integer(Arg),
    Bodies = offset_momentum(bodies()),
    E0 = energy(Bodies),
    E1 = energy(run(Steps, Bodies)),
    io:put_chars([integer_to_binary(scaled(E0)), "\n", integer_to_binary(scaled(E1)), "\n"]).

scaled(E) -> round(E * 1.0e9).

bodies() ->
    [{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, ?SOLAR_MASS},
     planet(4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
            1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
            9.54791938424326609e-04),
     planet(8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
            -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
            2.85885980666130812e-04),
     planet(1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
            2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
            4.36624404335156298e-05),
     planet(1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
            2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
            5.15138902046611451e-05)].

planet(X, Y, Z, Vx, Vy, Vz, Mass) ->
    {X, Y, Z, Vx * ?DAYS_PER_YEAR, Vy * ?DAYS_PER_YEAR, Vz * ?DAYS_PER_YEAR, Mass * ?SOLAR_MASS}.

offset_momentum([{X, Y, Z, _, _, _, M} | Planets] = Bodies) ->
    {Px, Py, Pz} = lists:foldl(
                     fun({_, _, _, Vx, Vy, Vz, Mass}, {Px, Py, Pz}) ->
                             {Px + Vx * Mass, Py + Vy * Mass, Pz + Vz * Mass}
                     end, {0.0, 0.0, 0.0}, Bodies),
    [{X, Y, Z, -Px / ?SOLAR_MASS, -Py / ?SOLAR_MASS, -Pz / ?SOLAR_MASS, M} | Planets].

energy(Bodies) -> energy(Bodies, 0.0).

energy([], E) -> E;
energy([{_, _, _, Vx, Vy, Vz, M} = B | Rest], E) ->
    E1 = E + 0.5 * M * (Vx * Vx + Vy * Vy + Vz * Vz),
    energy(Rest, potential(B, Rest, E1)).

potential(_, [], E) -> E;
potential({X, Y, Z, _, _, _, M} = A, [{X2, Y2, Z2, _, _, _, M2} | Rest], E) ->
    Dx = X - X2,
    Dy = Y - Y2,
    Dz = Z - Z2,
    potential(A, Rest, E - M * M2 / math:sqrt(Dx * Dx + Dy * Dy + Dz * Dz)).

run(0, Bodies) -> Bodies;
run(Steps, Bodies) -> run(Steps - 1, advance(Bodies)).

advance(Bodies) -> [move(B) || B <- pairs(Bodies)].

%% Interacts the first body with each later one in order, then recurses on the updated rest.
pairs([]) -> [];
pairs([A | Rest]) ->
    {A1, Rest1} = interact(A, Rest, []),
    [A1 | pairs(Rest1)].

interact(A, [], Acc) -> {A, lists:reverse(Acc)};
interact({X, Y, Z, Vx, Vy, Vz, M}, [{X2, Y2, Z2, Vx2, Vy2, Vz2, M2} | Rest], Acc) ->
    Dx = X - X2,
    Dy = Y - Y2,
    Dz = Z - Z2,
    D2 = Dx * Dx + Dy * Dy + Dz * Dz,
    Mag = ?DT / (D2 * math:sqrt(D2)),
    AMag = M * Mag,
    BMag = M2 * Mag,
    A1 = {X, Y, Z, Vx - Dx * BMag, Vy - Dy * BMag, Vz - Dz * BMag, M},
    B1 = {X2, Y2, Z2, Vx2 + Dx * AMag, Vy2 + Dy * AMag, Vz2 + Dz * AMag, M2},
    interact(A1, Rest, [B1 | Acc]).

move({X, Y, Z, Vx, Vy, Vz, M}) ->
    {X + ?DT * Vx, Y + ?DT * Vy, Z + ?DT * Vz, Vx, Vy, Vz, M}.
