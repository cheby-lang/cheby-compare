// nbody: simulates the Sun and the four giant planets, printing the energy before and after.

import std/os/env
import std/num/float64

struct body
  x : float64
  y : float64
  z : float64
  vx : float64
  vy : float64
  vz : float64
  mass : float64

val pi-value = 3.141592653589793
val solar-mass = 4.0 * pi-value * pi-value
val days-per-year = 365.24
val dt = 0.01

fun planet(x : float64, y : float64, z : float64, vx : float64, vy : float64, vz : float64, mass : float64) : body
  Body(x, y, z, vx * days-per-year, vy * days-per-year, vz * days-per-year, mass * solar-mass)

fun initial-bodies() : list<body>
  [ Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solar-mass),
    planet( 4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01,
            1.66007664274403694e-03,  7.69901118419740425e-03, -6.90460016972063023e-05,
            9.54791938424326609e-04),
    planet( 8.34336671824457987e+00,  4.12479856412430479e+00, -4.03523417114321381e-01,
           -2.76742510726862411e-03,  4.99852801234917238e-03,  2.30417297573763929e-05,
            2.85885980666130812e-04),
    planet( 1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01,
            2.96460137564761618e-03,  2.37847173959480950e-03, -2.96589568540237556e-05,
            4.36624404335156298e-05),
    planet( 1.53796971148509165e+01, -2.59193146099879641e+01,  1.79258772950371181e-01,
            2.68067772490389322e-03,  1.62824170038242295e-03, -9.51592254519715870e-05,
            5.15138902046611451e-05) ]

fun offset-momentum(bodies : list<body>) : list<body>
  val (px, py, pz) = bodies.foldl((0.0, 0.0, 0.0)) fn((px, py, pz), b)
    (px + b.vx * b.mass, py + b.vy * b.mass, pz + b.vz * b.mass)
  match bodies
    Cons(sun, rest) -> Cons(sun(vx = ~px / solar-mass, vy = ~py / solar-mass, vz = ~pz / solar-mass), rest)
    Nil -> Nil

// The potential energy between b and each body after it.
fun potential(b : body, rest : list<body>, e : float64) : float64
  match rest
    Nil -> e
    Cons(o, os) ->
      val dx = b.x - o.x
      val dy = b.y - o.y
      val dz = b.z - o.z
      potential(b, os, e - b.mass * o.mass / sqrt(dx * dx + dy * dy + dz * dz))

fun energy(bodies : list<body>, e : float64) : float64
  match bodies
    Nil -> e
    Cons(b, rest) ->
      val e1 = e + 0.5 * b.mass * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
      energy(rest, potential(b, rest, e1))

// Applies the pairs (a, b) for every b in `rest`, in order: the updated a and the updated rest.
fun interact(a : body, rest : list<body>) : (body, list<body>)
  match rest
    Nil -> (a, Nil)
    Cons(b, bs) ->
      val dx = a.x - b.x
      val dy = a.y - b.y
      val dz = a.z - b.z
      val d2 = dx * dx + dy * dy + dz * dz
      val mag = dt / (d2 * sqrt(d2))
      val a-mag = a.mass * mag
      val b-mag = b.mass * mag
      // Match and rebuild, not copy-update syntax (`a(vx = ...)`): Koka 3.2 compiles copy-update
      // through optional arguments, boxing every float64 field and never reusing the old body,
      // while a match followed by the constructor reuses a unique body in place.
      val a1 = match a
        Body(x, y, z, vx, vy, vz, m) -> Body(x, y, z, vx - dx * b-mag, vy - dy * b-mag, vz - dz * b-mag, m)
      val b1 = match b
        Body(x, y, z, vx, vy, vz, m) -> Body(x, y, z, vx + dx * a-mag, vy + dy * a-mag, vz + dz * a-mag, m)
      val (a2, bs2) = interact(a1, bs)
      (a2, Cons(b1, bs2))

// All pairs (0,1) (0,2) ... (3,4): the first body against each later one, then the rest.
fun velocities(bodies : list<body>) : div list<body>
  match bodies
    Nil -> Nil
    Cons(a, rest) ->
      val (a1, rest1) = interact(a, rest)
      Cons(a1, velocities(rest1))

fun advance(bodies : list<body>) : div list<body>
  velocities(bodies).map fn(b)
    match b
      Body(x, y, z, vx, vy, vz, m) -> Body(x + dt * vx, y + dt * vy, z + dt * vz, vx, vy, vz, m)

fun run(bodies : list<body>, steps : int) : div list<body>
  if steps <= 0 then bodies else run(advance(bodies), steps - 1)

// round(x) with halves away from zero.
fun round-away(x : float64) : int
  val t = x.truncate
  val r = if abs(x - t) >= 0.5 then t + (if x < 0.0 then -1.0 else 1.0) else t
  r.int

fun scaled(e : float64) : int
  round-away(e * 1.0e9)

pub fun main()
  val steps = get-args().head.default("0").parse-int.default(0)
  val bodies = offset-momentum(initial-bodies())
  println(scaled(energy(bodies, 0.0)).show)
  val after = run(bodies, steps)
  println(scaled(energy(after, 0.0)).show)
