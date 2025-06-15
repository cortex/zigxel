pub const RGB3 = packed struct {
    r: u1,
    g: u1,
    b: u1,
};
pub const RGB2x3 = packed struct {
    p1: RGB3,
    p2: RGB3,
};
pub const RGBA48 = packed struct {
    r: u16,
    g: u16,
    b: u16,
    a: u16,
};
pub const RGBA32 = packed struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,
};

pub const WHITE = RGBA32{ .a = 0x00, .r = 0xff, .g = 0xff, .b = 0xff };
pub const BLACK = RGBA32{ .a = 0x00, .r = 0x00, .g = 0x00, .b = 0x00 };
pub const RED = RGBA32{ .a = 0x00, .r = 0xff, .g = 0x00, .b = 0x00 };
pub const BLUE = RGBA32{ .a = 0x00, .r = 0x00, .g = 0x00, .b = 0xff };

pub fn hslToRgba(h: u8, s: u8, l: u8) RGBA32 {
    const h16: u16 = @intCast(h);
    const s16: u16 = @intCast(s);
    const l16: u16 = @intCast(l);

    const c = (255 - @abs(@as(i16, @intCast(2 * l16)) - 255)) * s16 / 255;
    const sector = h16 / 43; // 0 to 5
    const pos = h16 % 43;
    const x = c * (43 - @abs(@as(i16, @intCast(pos)) * 2 - 43)) / 43;

    const m = l16 - c / 2;

    var rf: u16 = 0;
    var gf: u16 = 0;
    var bf: u16 = 0;

    switch (sector) {
        0 => {
            rf = c + m;
            gf = x + m;
            bf = m;
        },
        1 => {
            rf = x + m;
            gf = c + m;
            bf = m;
        },
        2 => {
            rf = m;
            gf = c + m;
            bf = x + m;
        },
        3 => {
            rf = m;
            gf = x + m;
            bf = c + m;
        },
        4 => {
            rf = x + m;
            gf = m;
            bf = c + m;
        },
        5 => {
            rf = c + m;
            gf = m;
            bf = x + m;
        },
        else => {}, // shouldn't happen
    }

    return RGBA32{
        .r = @intCast(@min(rf, 255)),
        .g = @intCast(@min(gf, 255)),
        .b = @intCast(@min(bf, 255)),
        .a = 255,
    };
}
