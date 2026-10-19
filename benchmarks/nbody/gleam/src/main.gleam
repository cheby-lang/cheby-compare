//// N-body: the Sun and four giant planets, advanced in fixed steps; prints the energy before and after.

import gleam/float
import gleam/int
import gleam/io
import gleam/list

type Charlist

@external(erlang, "init", "get_plain_arguments")
fn plain_arguments() -> List(Charlist)

@external(erlang, "unicode", "characters_to_binary")
fn charlist_to_string(chars: Charlist) -> String

// The correctly rounded square root. gleam/float's square_root is math:pow(x, 0.5).
@external(erlang, "math", "sqrt")
fn sqrt(x: Float) -> Float

const pi = 3.141592653589793

// Gleam constants are literals only, so the derived value is a function.
fn solar_mass() -> Float {
  4.0 *. pi *. pi
}

const days_per_year = 365.24

const dt = 0.01

type Body {
  Body(
    x: Float,
    y: Float,
    z: Float,
    vx: Float,
    vy: Float,
    vz: Float,
    mass: Float,
  )
}

fn planet(
  x: Float,
  y: Float,
  z: Float,
  vx: Float,
  vy: Float,
  vz: Float,
  mass: Float,
) -> Body {
  Body(
    x,
    y,
    z,
    vx *. days_per_year,
    vy *. days_per_year,
    vz *. days_per_year,
    mass *. solar_mass(),
  )
}

fn bodies() -> List(Body) {
  [
    Body(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, solar_mass()),
    // Jupiter
    planet(
      4.8414314424647209e0,
      -1.16032004402742839e0,
      -1.03622044471123109e-1,
      1.66007664274403694e-3,
      7.69901118419740425e-3,
      -6.90460016972063023e-5,
      9.54791938424326609e-4,
    ),
    // Saturn
    planet(
      8.34336671824457987e0,
      4.12479856412430479e0,
      -4.03523417114321381e-1,
      -2.76742510726862411e-3,
      4.99852801234917238e-3,
      2.30417297573763929e-5,
      2.85885980666130812e-4,
    ),
    // Uranus
    planet(
      1.2894369562139131e1,
      -1.51111514016986312e1,
      -2.23307578892655734e-1,
      2.96460137564761618e-3,
      2.3784717395948095e-3,
      -2.96589568540237556e-5,
      4.36624404335156298e-5,
    ),
    // Neptune
    planet(
      1.53796971148509165e1,
      -2.59193146099879641e1,
      1.79258772950371181e-1,
      2.68067772490389322e-3,
      1.62824170038242295e-3,
      -9.5159225451971587e-5,
      5.15138902046611451e-5,
    ),
  ]
}

fn offset_momentum(bodies: List(Body)) -> List(Body) {
  let #(px, py, pz) =
    list.fold(bodies, #(0.0, 0.0, 0.0), fn(acc, b) {
      let #(px, py, pz) = acc
      #(px +. b.vx *. b.mass, py +. b.vy *. b.mass, pz +. b.vz *. b.mass)
    })
  let assert [sun, ..planets] = bodies
  [
    Body(
      ..sun,
      vx: float.negate(px) /. solar_mass(),
      vy: float.negate(py) /. solar_mass(),
      vz: float.negate(pz) /. solar_mass(),
    ),
    ..planets
  ]
}

fn energy(bodies: List(Body), e: Float) -> Float {
  case bodies {
    [] -> e
    [b, ..rest] -> {
      let e =
        e +. 0.5 *. b.mass *. { b.vx *. b.vx +. b.vy *. b.vy +. b.vz *. b.vz }
      energy(rest, potential(b, rest, e))
    }
  }
}

fn potential(a: Body, rest: List(Body), e: Float) -> Float {
  case rest {
    [] -> e
    [b, ..rest] -> {
      let dx = a.x -. b.x
      let dy = a.y -. b.y
      let dz = a.z -. b.z
      potential(
        a,
        rest,
        e -. a.mass *. b.mass /. sqrt(dx *. dx +. dy *. dy +. dz *. dz),
      )
    }
  }
}

/// Interacts the first body with each later one in order, then recurses on the updated rest.
fn pairs(bodies: List(Body)) -> List(Body) {
  case bodies {
    [] -> []
    [a, ..rest] -> {
      let #(a, rest) = interact(a, rest, [])
      [a, ..pairs(rest)]
    }
  }
}

fn interact(a: Body, rest: List(Body), acc: List(Body)) -> #(Body, List(Body)) {
  case rest {
    [] -> #(a, list.reverse(acc))
    [b, ..rest] -> {
      let dx = a.x -. b.x
      let dy = a.y -. b.y
      let dz = a.z -. b.z
      let d2 = dx *. dx +. dy *. dy +. dz *. dz
      let mag = dt /. { d2 *. sqrt(d2) }
      let a_mag = a.mass *. mag
      let b_mag = b.mass *. mag
      let a =
        Body(
          ..a,
          vx: a.vx -. dx *. b_mag,
          vy: a.vy -. dy *. b_mag,
          vz: a.vz -. dz *. b_mag,
        )
      let b =
        Body(
          ..b,
          vx: b.vx +. dx *. a_mag,
          vy: b.vy +. dy *. a_mag,
          vz: b.vz +. dz *. a_mag,
        )
      interact(a, rest, [b, ..acc])
    }
  }
}

fn move(b: Body) -> Body {
  Body(..b, x: b.x +. dt *. b.vx, y: b.y +. dt *. b.vy, z: b.z +. dt *. b.vz)
}

fn advance(bodies: List(Body)) -> List(Body) {
  list.map(pairs(bodies), move)
}

fn run(steps: Int, bodies: List(Body)) -> List(Body) {
  case steps {
    0 -> bodies
    _ -> run(steps - 1, advance(bodies))
  }
}

fn scaled(e: Float) -> Int {
  float.round(e *. 1.0e9)
}

pub fn main() -> Nil {
  let assert [arg, ..] = list.map(plain_arguments(), charlist_to_string)
  let assert Ok(steps) = int.parse(arg)

  let bodies = offset_momentum(bodies())
  io.println(int.to_string(scaled(energy(bodies, 0.0))))
  io.println(int.to_string(scaled(energy(run(steps, bodies), 0.0))))
}
