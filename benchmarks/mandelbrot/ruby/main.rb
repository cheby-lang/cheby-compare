# Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.

MAX_ITER = 50

# The number of iterations before c = cr + ci*i escapes, at most MAX_ITER.
def escape_time(cr, ci)
  zr = 0.0
  zi = 0.0
  i = 0
  while i < MAX_ITER
    zr2 = zr * zr
    zi2 = zi * zi
    break if zr2 + zi2 > 4.0

    zi = 2.0 * zr * zi + ci
    zr = zr2 - zi2 + cr
    i += 1
  end
  i
end

n = Integer(ARGV[0])
fn = n.to_f
inside = 0
iterations = 0
checksum = 0
n.times do |y|
  ci = 2.0 * y.to_f / fn - 1.0
  n.times do |x|
    cr = 2.0 * x.to_f / fn - 1.5
    i = escape_time(cr, ci)
    iterations += i
    if i == MAX_ITER
      inside += 1
      checksum += y * n + x
    end
  end
end
puts "inside #{inside}"
puts "iterations #{iterations}"
puts "checksum #{checksum % 2**32}"
