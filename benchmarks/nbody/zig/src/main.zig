//! n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
//! Prints the total energy before and after, as round(e * 10^9).

const std = @import("std");

const pi = std.math.pi;
const solar_mass = 4.0 * pi * pi;
const days_per_year = 365.24;
const dt = 0.01;

const Body = struct {
    x: f64,
    y: f64,
    z: f64,
    vx: f64,
    vy: f64,
    vz: f64,
    mass: f64,
};

fn planet(pos: [3]f64, vel: [3]f64, mass: f64) Body {
    return .{
        .x = pos[0],
        .y = pos[1],
        .z = pos[2],
        .vx = vel[0] * days_per_year,
        .vy = vel[1] * days_per_year,
        .vz = vel[2] * days_per_year,
        .mass = mass * solar_mass,
    };
}

fn initialBodies() [5]Body {
    const sun: Body = .{ .x = 0.0, .y = 0.0, .z = 0.0, .vx = 0.0, .vy = 0.0, .vz = 0.0, .mass = solar_mass };
    const jupiter = planet(
        .{ 4.84143144246472090e+00, -1.16032004402742839e+00, -1.03622044471123109e-01 },
        .{ 1.66007664274403694e-03, 7.69901118419740425e-03, -6.90460016972063023e-05 },
        9.54791938424326609e-04,
    );
    const saturn = planet(
        .{ 8.34336671824457987e+00, 4.12479856412430479e+00, -4.03523417114321381e-01 },
        .{ -2.76742510726862411e-03, 4.99852801234917238e-03, 2.30417297573763929e-05 },
        2.85885980666130812e-04,
    );
    const uranus = planet(
        .{ 1.28943695621391310e+01, -1.51111514016986312e+01, -2.23307578892655734e-01 },
        .{ 2.96460137564761618e-03, 2.37847173959480950e-03, -2.96589568540237556e-05 },
        4.36624404335156298e-05,
    );
    const neptune = planet(
        .{ 1.53796971148509165e+01, -2.59193146099879641e+01, 1.79258772950371181e-01 },
        .{ 2.68067772490389322e-03, 1.62824170038242295e-03, -9.51592254519715870e-05 },
        5.15138902046611451e-05,
    );
    return .{ sun, jupiter, saturn, uranus, neptune };
}

fn offsetMomentum(bodies: []Body) void {
    var px: f64 = 0.0;
    var py: f64 = 0.0;
    var pz: f64 = 0.0;
    for (bodies) |b| {
        px += b.vx * b.mass;
        py += b.vy * b.mass;
        pz += b.vz * b.mass;
    }
    bodies[0].vx = -px / solar_mass;
    bodies[0].vy = -py / solar_mass;
    bodies[0].vz = -pz / solar_mass;
}

fn energy(bodies: []const Body) f64 {
    var e: f64 = 0.0;
    for (bodies, 0..) |bi, i| {
        e += 0.5 * bi.mass * (bi.vx * bi.vx + bi.vy * bi.vy + bi.vz * bi.vz);
        for (bodies[i + 1 ..]) |bj| {
            const dx = bi.x - bj.x;
            const dy = bi.y - bj.y;
            const dz = bi.z - bj.z;
            e -= bi.mass * bj.mass / @sqrt(dx * dx + dy * dy + dz * dz);
        }
    }
    return e;
}

fn advance(bodies: []Body) void {
    for (bodies, 0..) |*bi, i| {
        for (bodies[i + 1 ..]) |*bj| {
            const dx = bi.x - bj.x;
            const dy = bi.y - bj.y;
            const dz = bi.z - bj.z;
            const d2 = dx * dx + dy * dy + dz * dz;
            const mag = dt / (d2 * @sqrt(d2));
            const mi_mag = bi.mass * mag;
            const mj_mag = bj.mass * mag;
            bi.vx -= dx * mj_mag;
            bi.vy -= dy * mj_mag;
            bi.vz -= dz * mj_mag;
            bj.vx += dx * mi_mag;
            bj.vy += dy * mi_mag;
            bj.vz += dz * mi_mag;
        }
    }
    for (bodies) |*b| {
        b.x += dt * b.vx;
        b.y += dt * b.vy;
        b.z += dt * b.vz;
    }
}

fn scaled(e: f64) i64 {
    return @intFromFloat(@round(e * 1e9));
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.MissingArgument;
    const steps = try std.fmt.parseInt(u64, args[1], 10);

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var bodies = initialBodies();
    offsetMomentum(&bodies);
    try stdout.print("{d}\n", .{scaled(energy(&bodies))});
    var step: u64 = 0;
    while (step < steps) : (step += 1) {
        advance(&bodies);
    }
    try stdout.print("{d}\n", .{scaled(energy(&bodies))});
    try stdout.flush();
}
