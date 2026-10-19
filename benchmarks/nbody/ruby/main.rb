# n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
#
# Prints the total energy before and after, as round(e * 10^9).

PI = 3.141592653589793
SOLAR_MASS = 4.0 * PI * PI
DAYS_PER_YEAR = 365.24
DT = 0.01

class Body
  attr_accessor :x, :y, :z, :vx, :vy, :vz, :mass

  def initialize(x, y, z, vx, vy, vz, mass)
    @x = x
    @y = y
    @z = z
    @vx = vx
    @vy = vy
    @vz = vz
    @mass = mass
  end
end

def planet(pos, vel, mass)
  Body.new(
    pos[0], pos[1], pos[2],
    vel[0] * DAYS_PER_YEAR, vel[1] * DAYS_PER_YEAR, vel[2] * DAYS_PER_YEAR,
    mass * SOLAR_MASS
  )
end

def initial_bodies
  sun = Body.new(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS)
  jupiter = planet(
    [4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01],
    [1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05],
    9.54791938424326609e-04
  )
  saturn = planet(
    [8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01],
    [-2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05],
    2.85885980666130812e-04
  )
  uranus = planet(
    [1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01],
    [2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05],
    4.36624404335156298e-05
  )
  neptune = planet(
    [1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01],
    [2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05],
    5.15138902046611451e-05
  )
  [sun, jupiter, saturn, uranus, neptune]
end

def offset_momentum(bodies)
  px = py = pz = 0.0
  bodies.each do |b|
    px += b.vx * b.mass
    py += b.vy * b.mass
    pz += b.vz * b.mass
  end
  sun = bodies[0]
  sun.vx = -px / SOLAR_MASS
  sun.vy = -py / SOLAR_MASS
  sun.vz = -pz / SOLAR_MASS
end

def energy(bodies)
  e = 0.0
  bodies.each_with_index do |bi, i|
    e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz)
    (i + 1...bodies.size).each do |j|
      bj = bodies[j]
      dx = bi.x - bj.x
      dy = bi.y - bj.y
      dz = bi.z - bj.z
      e -= bi.mass * bj.mass / Math.sqrt(dx * dx + dy * dy + dz * dz)
    end
  end
  e
end

# One time step. `pairs` lists the body pairs (i, j), i < j, in the order of the nested loops.
def advance(pairs, bodies)
  pairs.each do |bi, bj|
    dx = bi.x - bj.x
    dy = bi.y - bj.y
    dz = bi.z - bj.z
    d2 = dx * dx + dy * dy + dz * dz
    mag = DT / (d2 * Math.sqrt(d2))
    bi_mag = bi.mass * mag
    bj_mag = bj.mass * mag
    bi.vx -= dx * bj_mag
    bi.vy -= dy * bj_mag
    bi.vz -= dz * bj_mag
    bj.vx += dx * bi_mag
    bj.vy += dy * bi_mag
    bj.vz += dz * bi_mag
  end
  bodies.each do |b|
    b.x += DT * b.vx
    b.y += DT * b.vy
    b.z += DT * b.vz
  end
end

# round(e * 10^9), halves away from zero (Float#round's default).
def scaled(e) = (e * 1.0e9).round

steps = Integer(ARGV[0])
bodies = initial_bodies
offset_momentum(bodies)
puts scaled(energy(bodies))
pairs = bodies.combination(2).to_a
steps.times { advance(pairs, bodies) }
puts scaled(energy(bodies))
