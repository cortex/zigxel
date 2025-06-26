const microzig = @import("microzig");
const hal = microzig.hal;
const std = @import("std");
const color = @import("color.zig");
const image = @import("image.zig");

pub fn draw_clear(img: image.DynamicImage(color.RGBA32), c: color.RGBA32) void {
    for (0..img.width) |x| {
        for (0..img.height) |y| {
            img.write(x, y, c);
        }
    }
}

fn red(v: u8) color.RGBA32 {
    return color.RGBA32{ .r = v, .g = 0, .b = 0, .a = 255 };
}

fn fire_color(v: u8) color.RGBA32 {
    if (v < 128) {
        return color.RGBA32{ .r = v, .g = v, .b = v, .a = 255 };
    } else if (v < 160) {
        return color.RGBA32{ .r = v * 2, .g = 0, .b = 0, .a = 255 };
    } else if (v < 192) {
        return color.RGBA32{ .r = 255, .g = (v - 128) * 2, .b = 0, .a = 255 };
    } else {
        return color.RGBA32{ .r = 255, .g = 255, .b = (v - 192) * 2, .a = 255 };
    }
}
const Ascon = hal.rand.Ascon;
pub const Fire = struct {
    map: image.StaticImage(u8, 64, 32),
    pub fn step(self: *@This()) void {
        var ascon = Ascon.init();
        var rng = ascon.random();
        for (0..self.map.width) |x| {
            for (0..self.map.height) |y| {
                const v: u8 =
                    if (x == self.map.width - 1) (blk: {
                        const old_v: i16 = self.map.read(x, y);
                        const new: i16 = @divTrunc((rng.int(i8)), 30);
                        break :blk @intCast(old_v + new);
                    }) else blk: {
                        const p1: u32 = if (y > 0)
                            self.map.read(x + 1, y - 1)
                        else
                            0;
                        const p2: u32 = self.map.read(x + 1, y);
                        const p3: u32 = self.map.read(x + 1, y + 1);
                        break :blk @intCast((999 * (p1 / 2 + p2 + p3 / 2) / 2000));
                    };
                self.map.write(x, y, v);
            }
        }
    }
    pub fn draw(self: @This(), img: image.DynamicImage(color.RGBA32)) void {
        for (0..img.width) |x| {
            for (0..img.height) |y| {
                const c = self.map.read(x, y);
                img.write(x, y, fire_color(c));
            }
        }
    }

    pub fn init() @This() {
        return .{ .map = .{} };
    }
};

//v is value between 0.255
fn rainbow(v: u8) color.RGBA32 {
    const n: u8 = 6;
    const d: u8 = 43;
    const segment = v / d;
    const vs = v % d; // range 0-d
    var c = color.RGBA32{};

    const up = vs * n;
    const down = (d - vs) * n;

    switch (segment) {
        //red to yellow
        0 => {
            c.r = 255;
            c.g = up;
        },
        //yellow to green
        1 => {
            c.r = down;
            c.g = 255;
        },
        //green to teal
        2 => {
            c.g = 255;
            c.b = up;
        },
        // teal to blue
        3 => {
            c.b = 255;
            c.g = down;
        },
        // blue to violet
        4 => {
            c.b = 255;
            c.r = up;
        },
        // violet to red
        5 => {
            c.r = 255;
            c.b = down;
        },
        else => unreachable, // shouldn't happen
    }
    return c;
}

pub fn draw_rainbow(img: image.DynamicImage(color.RGBA32), t: u64) void {
    for (0..img.width) |x| {
        for (0..img.height) |y| {
            const x8: u8 = @intCast(x * 255 / img.width);
            const y8: u8 = @intCast(y * 255 / img.height);
            // _ = y8;
            const t8: u8 = @intCast(t / 2);
            const c = rainbow(x8 +% y8 +% t8);
            // std.log.info("x: {} x8: {} c {}", .{ x, x8, c });
            img.write(x, y, c);
        }
    }
}

const DrawOptions = struct {
    src_x: usize,
    src_y: usize,
    w: usize,
    h: usize,
};

pub fn draw_image(
    dest: image.DynamicImage(color.RGBA32),
    src: image.DynamicImage(color.RGBA32),
    x: usize,
    y: usize,
    opts: DrawOptions,
) void {
    for (0..opts.w) |w| {
        for (0..opts.h) |h| {
            const c = src.read(opts.src_x + w, opts.src_y + h);
            if ((x + h) < dest.width and (y + w) < dest.height) {
                if (c == color.WHITE) {
                    dest.write(x + h, y + w, color.RED);
                }
            }
        }
    }
}

fn blend(from: u8, to: u8, steps: u8, step: u8) u8 {
    if (steps == 0) return from;
    const l: i32 = @as(i32, to) - @as(i32, from);
    const result = @as(i32, from) + @divTrunc(l * @as(i32, step), @as(i32, steps));
    return @intCast(@max(0, @min(255, result)));
}

fn blend_color(from: color.RGBA32, to: color.RGBA32, steps: u8, step: u8) color.RGBA32 {
    const r = blend(from.r, to.r, steps, step);
    const g = blend(from.g, to.g, steps, step);
    const b = blend(from.b, to.b, steps, step);
    const a = blend(from.a, to.a, steps, step);
    return color.RGBA32.init(r, g, b, a);
}

fn gradient(comptime steps: []const color.RGBA32) [255]color.RGBA32 {
    @setEvalBranchQuota(2000);
    var lut: [255]color.RGBA32 = undefined;

    for (0..255) |i| {
        // Map LUT index to position in gradient using fixed-point arithmetic
        // Scale i by (steps.len - 1) to get position across all segments
        const scaled_pos = i * (steps.len - 1);

        // Find which segment this position falls into
        const segment: u8 = @min(scaled_pos / 254, steps.len - 2);

        // Calculate position within the segment (0 to 254)
        const segment_start = segment * 254;
        const local_pos = scaled_pos - segment_start;

        // Scale local position to 0-255 range for blending
        const blend_step: u8 = @intCast((local_pos * 255) / 254);

        lut[i] = blend_color(steps[segment], steps[segment + 1], 255, blend_step);
    }

    return lut;
}

const bw = gradient(&[_]color.RGBA32{ color.BLACK, color.WHITE });

pub fn draw_with_func(img: image.DynamicImage(color.RGBA32), t: u64, comptime draw_fn: fn (usize, usize, u64) color.RGBA32) void {
    for (0..img.width) |x| {
        for (0..img.height) |y| {
            const c = draw_fn(x, y, t);
            img.write(x, y, c);
        }
    }
}

pub fn gradient_draw(x: usize, _: usize, _: u64) color.RGBA32 {
    const step: u8 = @intCast((x * 4) % 255);
    return bw[step];
}
