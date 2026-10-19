defmodule Main do
  @moduledoc "N-body: the Sun and four giant planets, advanced in fixed steps; prints the energy before and after."

  @pi 3.141592653589793
  @solar_mass 4.0 * @pi * @pi
  @days_per_year 365.24
  @dt 0.01

  # A body is {x, y, z, vx, vy, vz, mass}; the system is a list of five bodies.

  def main do
    [arg | _] = :init.get_plain_arguments()
    steps = arg |> List.to_string() |> String.to_integer()

    bodies = offset_momentum(bodies())
    e0 = energy(bodies)
    e1 = energy(run(steps, bodies))

    IO.write([Integer.to_string(scaled(e0)), "\n", Integer.to_string(scaled(e1)), "\n"])
  end

  defp scaled(e), do: round(e * 1.0e9)

  defp bodies do
    [
      {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, @solar_mass},
      planet(
        4.84143144246472090e+00,
        -1.16032004402742839e+00,
        -1.03622044471123109e-01,
        1.66007664274403694e-03,
        7.69901118419740425e-03,
        -6.90460016972063023e-05,
        9.54791938424326609e-04
      ),
      planet(
        8.34336671824457987e+00,
        4.12479856412430479e+00,
        -4.03523417114321381e-01,
        -2.76742510726862411e-03,
        4.99852801234917238e-03,
        2.30417297573763929e-05,
        2.85885980666130812e-04
      ),
      planet(
        1.28943695621391310e+01,
        -1.51111514016986312e+01,
        -2.23307578892655734e-01,
        2.96460137564761618e-03,
        2.37847173959480950e-03,
        -2.96589568540237556e-05,
        4.36624404335156298e-05
      ),
      planet(
        1.53796971148509165e+01,
        -2.59193146099879641e+01,
        1.79258772950371181e-01,
        2.68067772490389322e-03,
        1.62824170038242295e-03,
        -9.51592254519715870e-05,
        5.15138902046611451e-05
      )
    ]
  end

  defp planet(x, y, z, vx, vy, vz, mass) do
    {x, y, z, vx * @days_per_year, vy * @days_per_year, vz * @days_per_year, mass * @solar_mass}
  end

  defp offset_momentum([{x, y, z, _, _, _, m} | planets] = bodies) do
    {px, py, pz} =
      Enum.reduce(bodies, {0.0, 0.0, 0.0}, fn {_, _, _, vx, vy, vz, mass}, {px, py, pz} ->
        {px + vx * mass, py + vy * mass, pz + vz * mass}
      end)

    [{x, y, z, -px / @solar_mass, -py / @solar_mass, -pz / @solar_mass, m} | planets]
  end

  defp energy(bodies), do: energy(bodies, 0.0)

  defp energy([], e), do: e

  defp energy([{_, _, _, vx, vy, vz, m} = b | rest], e) do
    e = e + 0.5 * m * (vx * vx + vy * vy + vz * vz)
    energy(rest, potential(b, rest, e))
  end

  defp potential(_, [], e), do: e

  defp potential({x, y, z, _, _, _, m} = a, [{x2, y2, z2, _, _, _, m2} | rest], e) do
    dx = x - x2
    dy = y - y2
    dz = z - z2
    potential(a, rest, e - m * m2 / :math.sqrt(dx * dx + dy * dy + dz * dz))
  end

  defp run(0, bodies), do: bodies
  defp run(steps, bodies), do: run(steps - 1, advance(bodies))

  defp advance(bodies), do: bodies |> pairs() |> Enum.map(&move/1)

  # Interacts the first body with each later one in order, then recurses on the updated rest.
  defp pairs([]), do: []

  defp pairs([a | rest]) do
    {a, rest} = interact(a, rest, [])
    [a | pairs(rest)]
  end

  defp interact(a, [], acc), do: {a, Enum.reverse(acc)}

  defp interact({x, y, z, vx, vy, vz, m}, [{x2, y2, z2, vx2, vy2, vz2, m2} | rest], acc) do
    dx = x - x2
    dy = y - y2
    dz = z - z2
    d2 = dx * dx + dy * dy + dz * dz
    mag = @dt / (d2 * :math.sqrt(d2))
    a_mag = m * mag
    b_mag = m2 * mag
    a = {x, y, z, vx - dx * b_mag, vy - dy * b_mag, vz - dz * b_mag, m}
    b = {x2, y2, z2, vx2 + dx * a_mag, vy2 + dy * a_mag, vz2 + dz * a_mag, m2}
    interact(a, rest, [b | acc])
  end

  defp move({x, y, z, vx, vy, vz, m}) do
    {x + @dt * vx, y + @dt * vy, z + @dt * vz, vx, vy, vz, m}
  end
end
