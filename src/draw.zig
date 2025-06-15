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

fn draw_rainbow(img: color.Image, t: u64) void {
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
                    dest.write(x + h, y + w, c);
                }
            }
        }
    }
}
