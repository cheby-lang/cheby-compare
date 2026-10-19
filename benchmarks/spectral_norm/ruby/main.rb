# Spectral norm: the benchmarks-game power method on the matrix
# A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.

# A(i, j), with the denominator in integers.
def a(i, j)
  ij = i + j
  1.0 / (ij * (ij + 1) / 2 + i + 1)
end

# out = A x
def times_a(x, out)
  n = x.size
  i = 0
  while i < n
    sum = 0.0
    j = 0
    while j < n
      sum += a(i, j) * x[j]
      j += 1
    end
    out[i] = sum
    i += 1
  end
  out
end

# out = A^T x
def times_at(x, out)
  n = x.size
  i = 0
  while i < n
    sum = 0.0
    j = 0
    while j < n
      sum += a(j, i) * x[j]
      j += 1
    end
    out[i] = sum
    i += 1
  end
  out
end

# out = A^T A x, through the scratch vector tmp.
def times_ata(x, out, tmp) = times_at(times_a(x, tmp), out)

def dot(x, y)
  sum = 0.0
  x.each_with_index { |xi, i| sum += xi * y[i] }
  sum
end

n = Integer(ARGV[0])
u = Array.new(n, 1.0)
v = Array.new(n, 0.0)
tmp = Array.new(n, 0.0)
10.times do
  times_ata(u, v, tmp)
  times_ata(v, u, tmp)
end
vv = dot(v, v)
# Float#round rounds halves away from zero.
puts(vv == 0.0 ? 0 : (Math.sqrt(dot(u, v) / vv) * 1.0e9).round)
