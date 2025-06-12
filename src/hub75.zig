const std = @import("std");
const colors = @import("color.zig");
const microzig = @import("microzig");
const hal = microzig.hal;

fn write_addr(h: Hub75, addr: Addr) void {
    h.pins.addr_a.put(~addr.a);
    h.pins.addr_b.put(~addr.b);
    h.pins.addr_c.put(~addr.c);
    h.pins.addr_d.put(~addr.d);
}

const Pin = hal.gpio.Pin;

pub const Hub75 = struct {
    pins: struct {
        addr_a: Pin,
        addr_b: Pin,
        addr_c: Pin,
        addr_d: Pin,
        latch: Pin,
        clk: Pin,
        output_enable: Pin,
    },

    pub fn init(h: *Hub75) void {
        h.pins.addr_a.set_direction(.out);
        h.pins.addr_b.set_direction(.out);
        h.pins.addr_c.set_direction(.out);
        h.pins.addr_d.set_direction(.out);
        init_rgb_pio();
        if (latch_pio_enabled) {
            init_latch_addr_pio();
        }
    }
};

const rgb_pio: hal.pio.Pio = hal.pio.num(0);
const rgb_statemachine: hal.pio.StateMachine = .sm0;

const put_rgb_program = blk: {
    @setEvalBranchQuota(8000);
    break :blk hal.pio.assemble(
        \\.program put_rgb
        \\ set pindirs, 1
        \\ .wrap_target
        \\    pull
        \\    out pins 6
        \\    set pins 0b001 [1]
        \\    set pins 0b000 [1]
        \\    out pins 6
        \\    set pins 0b001 [1]
        \\    set pins 0b000 [1]
    , .{}).get_program_by_name("put_rgb");
};

fn init_rgb_pio() void {
    for (0..6) |pin| {
        rgb_pio.gpio_init(hal.gpio.num(@intCast(pin)));
    }
    rgb_pio.gpio_init(hal.gpio.num(10));
    // rgb_pio.gpio_init(rp2xxx.gpio.num(11));
    // rgb_pio.gpio_init(rp2xxx.gpio.num(12));
    rgb_pio.sm_load_and_start_program(rgb_statemachine, put_rgb_program, .{
        .clkdiv = hal.pio.ClkDivOptions.from_float(1),
        .pin_mappings = .{ .out = .{
            .base = 0,
            .count = 6,
        }, .set = .{
            .base = 10,
            .count = 1,
        } },
        .shift = .{
            .out_shiftdir = .left,
        },
    }) catch unreachable;
    std.log.info("Initialized pio", .{});
    rgb_pio.sm_set_shift_options(rgb_statemachine, .{
        .join_tx = true,
    });
    rgb_pio.sm_set_pindir(rgb_statemachine, 0, 6, .out);
    // rgb_pio.sm_set_pindir(rgb_statemachine, 10, 1, .out);
    rgb_pio.sm_set_enabled(rgb_statemachine, true);
}

inline fn write_packed_rgb_fifo(pp1: colors.RGB2x3, pp2: colors.RGB2x3) void {
    const p1: u32 = @intCast(@as(u6, @bitCast(pp1)));
    const p2: u32 = @intCast(@as(u6, @bitCast(pp2)));
    const pu32: u32 = (p2 << 6) | p1;
    rgb_pio.sm_write(rgb_statemachine, pu32);
}

inline fn write_addr_fifo(a: u32) void {
    latch_addr_pio.sm_write(latch_addr_statemachine, ~a);
}

const latch_pio_enabled = true;

const latch_addr_program = blk: {
    @setEvalBranchQuota(8000);
    break :blk hal.pio.assemble(
        \\.program latch_addr
        \\ set pindirs 0b11
        \\ again:
        \\ pull block
        \\ out pins 4
        \\ set pins 0b01 [4]
        \\ set pins 0b00 [4]
        \\ set pins 0b10 [4]
        \\ set pins 0b00 [4]
        \\ jmp again
    , .{}).get_program_by_name("latch_addr");
};

const latch_addr_pio: hal.pio.Pio = hal.pio.num(1);
const latch_addr_statemachine: hal.pio.StateMachine = .sm0;
fn init_latch_addr_pio() void {
    for (6..10) |pin| {
        latch_addr_pio.gpio_init(hal.gpio.num(@intCast(pin)));
    }
    latch_addr_pio.gpio_init(hal.gpio.num(11));
    latch_addr_pio.gpio_init(hal.gpio.num(12));
    latch_addr_pio.sm_load_and_start_program(
        latch_addr_statemachine,
        latch_addr_program,
        .{
            .clkdiv = hal.pio.ClkDivOptions.from_float(1),
            .pin_mappings = .{
                .out = .{
                    .base = 6,
                    .count = 4,
                },
                .set = .{
                    .base = 11,
                    .count = 2,
                },
            },
            .shift = .{
                .out_shiftdir = .right,
            },
        },
    ) catch unreachable;
    std.log.info("Initialized latch pio", .{});
    latch_addr_pio.sm_set_shift_options(latch_addr_statemachine, .{
        .join_tx = true,
    });
    latch_addr_pio.sm_set_pindir(latch_addr_statemachine, 6, 4, .out);
    latch_addr_pio.sm_set_enabled(latch_addr_statemachine, true);
}

const Addr = packed struct {
    a: u1,
    b: u1,
    c: u1,
    d: u1,
    fn U4(v: u4) Addr {
        return @bitCast(v);
    }
    fn U32(v: u32) Addr {
        return U4(@intCast(v));
    }
};

pub const ROWS: usize = 32;
pub const COLS: usize = 64;
const PACKED_ROWS = ROWS >> 1;

// var framebuffer: [PACKED_ROWS * COLS]u6 = undefined;

const gamma_lut: [256]u8 = blk: {
    @setEvalBranchQuota(20000);
    const gamma = 2.2;
    var tbl: [256]u8 = undefined;
    for (0..256) |i| {
        const c = @as(f32, i) / 255.0;
        const lin = if (c <= 0.04045)
            c / 12.92
        else
            std.math.pow(f32, (c + 0.055) / 1.055, gamma);
        // Rescale to TIME_DITHER_STEPS
        tbl[i] = @intFromFloat(lin * TIME_DITHER_STEPS);
    }
    break :blk tbl;
};

const TIME_DITHER_STEPS = 8;
inline fn td_on(v: usize, t: usize) u1 {
    return @intFromBool(gamma_lut[v] > t);
}

inline fn temporal_dither(color: colors.RGBA32, t: usize) colors.RGB3 {
    return colors.RGB3{
        .r = td_on(color.r, t),
        .g = td_on(color.g, t),
        .b = td_on(color.b, t),
    };
}

const buffer = @import("buffer.zig");
inline fn temporal_rgbbuf(buf: colors.Image, x: usize, y: usize, t: usize) colors.RGB3 {
    const color_rgb: colors.RGBA32 = buf.read(x, y);
    return temporal_dither(color_rgb, @intCast(t));
}

pub fn scanout(_: Hub75, b: *buffer.DoubleBuffer) void {
    b.lock();
    const fb = b.front();
    b.unlock();
    var data: [COLS]colors.RGB2x3 = undefined;
    for (0..(TIME_DITHER_STEPS)) |t| {
        for (0..PACKED_ROWS) |r| {
            for (0..COLS) |c| {
                const x = c;
                const y1 = r;
                const y2 = y1 + 16;
                const p1 = temporal_rgbbuf(fb, x, y1, t);
                const p2 = temporal_rgbbuf(fb, x, y2, t);
                const d = colors.RGB2x3{ .p1 = p2, .p2 = p1 };
                data[c] = d;
                // write_packed_rgb_fifo(d);
            }
            for (0..(COLS / 2)) |c| {
                write_packed_rgb_fifo(data[2 * c], data[2 * c + 1]);
            }
            write_addr_fifo(r);
        }
    }
}
pub var scanout_fps: u32 = 0;

pub fn scanout_forever(h: Hub75, b: *buffer.DoubleBuffer) void {
    var i: usize = 0;
    var t = hal.time.get_time_since_boot();
    while (true) {
        scanout(h, b);
        i = i + 1;
        if (i > 100) {
            const nt = hal.time.get_time_since_boot();
            scanout_fps = @intCast(i * 1_000_000 / nt.diff(t).to_us());
            i = 0;
            t = nt;
        }
    }
}
