// n-body: the Sun and four giant planets under gravity, advanced in fixed steps.
// Prints the total energy before and after, as round(e * 10^9).

val SolarMass = 4.0 * math.Pi * math.Pi
val DaysPerYear = 365.24
val Dt = 0.01

final class Body(
    var x: Double, var y: Double, var z: Double,
    var vx: Double, var vy: Double, var vz: Double,
    val mass: Double,
)

def planet(x: Double, y: Double, z: Double, vx: Double, vy: Double, vz: Double, mass: Double): Body =
  Body(x, y, z, vx * DaysPerYear, vy * DaysPerYear, vz * DaysPerYear, mass * SolarMass)

def initialBodies(): Array[Body] = Array(
  Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SolarMass),
  planet( // Jupiter
    4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
    1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05,
    9.54791938424326609e-04),
  planet( // Saturn
    8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01,
    -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05,
    2.85885980666130812e-04),
  planet( // Uranus
    1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
    2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05,
    4.36624404335156298e-05),
  planet( // Neptune
    1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01,
    2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05,
    5.15138902046611451e-05),
)

def offsetMomentum(bodies: Array[Body]): Unit =
  var px = 0.0
  var py = 0.0
  var pz = 0.0
  for b <- bodies do
    px = px + b.vx * b.mass
    py = py + b.vy * b.mass
    pz = pz + b.vz * b.mass
  val sun = bodies(0)
  sun.vx = -px / SolarMass
  sun.vy = -py / SolarMass
  sun.vz = -pz / SolarMass

def energy(bodies: Array[Body]): Double =
  var e = 0.0
  var i = 0
  while i < bodies.length do
    val b = bodies(i)
    e = e + 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
    var j = i + 1
    while j < bodies.length do
      val o = bodies(j)
      val dx = b.x - o.x
      val dy = b.y - o.y
      val dz = b.z - o.z
      e = e - b.mass * o.mass / math.sqrt(dx * dx + dy * dy + dz * dz)
      j += 1
    i += 1
  e

def advance(bodies: Array[Body]): Unit =
  val n = bodies.length
  var i = 0
  while i < n do
    val a = bodies(i)
    var j = i + 1
    while j < n do
      val b = bodies(j)
      val dx = a.x - b.x
      val dy = a.y - b.y
      val dz = a.z - b.z
      val d2 = dx * dx + dy * dy + dz * dz
      val mag = Dt / (d2 * math.sqrt(d2))
      val aMag = a.mass * mag
      val bMag = b.mass * mag
      a.vx = a.vx - dx * bMag
      a.vy = a.vy - dy * bMag
      a.vz = a.vz - dz * bMag
      b.vx = b.vx + dx * aMag
      b.vy = b.vy + dy * aMag
      b.vz = b.vz + dz * aMag
      j += 1
    i += 1
  i = 0
  while i < n do
    val b = bodies(i)
    b.x = b.x + Dt * b.vx
    b.y = b.y + Dt * b.vy
    b.z = b.z + Dt * b.vz
    i += 1

/** round(e * 1e9), halves away from zero. */
def scaled(e: Double): Long =
  val x = e * 1.0e9
  if x < 0 then -math.round(-x) else math.round(x)

@main def main(steps: Int): Unit =
  val bodies = initialBodies()
  offsetMomentum(bodies)
  println(scaled(energy(bodies)))
  var s = 0
  while s < steps do
    advance(bodies)
    s += 1
  println(scaled(energy(bodies)))
