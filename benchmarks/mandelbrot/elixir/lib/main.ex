defmodule Main do
  @moduledoc "Mandelbrot: escape-time iteration on an N x N grid, printing counts and a checksum."

  import Bitwise

  @max_iter 50

  def main do
    [arg | _] = :init.get_plain_arguments()
    n = arg |> List.to_string() |> String.to_integer()

    {inside, iterations, checksum} = rows(0, n, :erlang.float(n), 0, 0, 0)

    IO.write([
      "inside ",
      Integer.to_string(inside),
      "\niterations ",
      Integer.to_string(iterations),
      "\nchecksum ",
      Integer.to_string(checksum &&& 0xFFFFFFFF),
      "\n"
    ])
  end

  defp rows(n, n, _nf, inside, iters, sum), do: {inside, iters, sum}

  defp rows(y, n, nf, inside, iters, sum) do
    ci = 2.0 * :erlang.float(y) / nf - 1.0
    {inside, iters, sum} = cols(0, y, n, nf, ci, inside, iters, sum)
    rows(y + 1, n, nf, inside, iters, sum)
  end

  defp cols(n, _y, n, _nf, _ci, inside, iters, sum), do: {inside, iters, sum}

  defp cols(x, y, n, nf, ci, inside, iters, sum) do
    cr = 2.0 * :erlang.float(x) / nf - 1.5

    case escape(0.0, 0.0, cr, ci, 0) do
      @max_iter -> cols(x + 1, y, n, nf, ci, inside + 1, iters + @max_iter, sum + (y * n + x))
      i -> cols(x + 1, y, n, nf, ci, inside, iters + i, sum)
    end
  end

  defp escape(_zr, _zi, _cr, _ci, @max_iter), do: @max_iter

  defp escape(zr, zi, cr, ci, i) do
    zr2 = zr * zr
    zi2 = zi * zi

    if zr2 + zi2 > 4.0 do
      i
    else
      escape(zr2 - zi2 + cr, 2.0 * zr * zi + ci, cr, ci, i + 1)
    end
  end
end
