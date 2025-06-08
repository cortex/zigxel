const std = @import("std");
const colors = @import("color.zig");
const microzig = @import("microzig");
const hal = microzig.hal;

// Write RGB 2x and pulse clock
// fn write_packed_rgb(pp: colors.RGB2x3) void {
//     pins.r0.put(pp.p2.r);
//     pins.g0.put(pp.p2.g);
//     pins.b0.put(pp.p2.b);
//     pins.r1.put(pp.p1.r);
//     pins.g1.put(pp.p1.g);
//     pins.b1.put(pp.p1.b);

//     pins.clk.put(1);
//     std.atomic.spinLoopHint();
//     // time.sleep_us(1);
//     pins.clk.put(0);

//     std.atomic.spinLoopHint();
//     // time.sleep_us(1);
// }

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

    pub fn init(_: Hub75) void {
        init_pio();
    }
};

const rgb_pio: hal.pio.Pio = hal.pio.num(0);
const rgb_statemachine: hal.pio.StateMachine = .sm0;

const put_rgb_program = blk: {
    @setEvalBranchQuota(3000);
    break :blk hal.pio.assemble(
        \\.program put_rgb
        \\ set pindirs, 1
        \\    pull
        \\    out pins 6
        \\    set pins 1 [1]
        \\    set pins 0 [1]
    , .{}).get_program_by_name("put_rgb");
};

fn init_pio() void {
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
            .count = 3,
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
    rgb_pio.sm_set_pindir(rgb_statemachine, 10, 1, .out);
    rgb_pio.sm_set_enabled(rgb_statemachine, true);
}

pub fn write_packed_rgb_fifo(pp: colors.RGB2x3) void {
    const pu32: u32 = @intCast(@as(u6, @bitCast(pp)));
    const d: u32 = pu32;
    rgb_pio.sm_blocking_write(rgb_statemachine, d);
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
    var tbl: [256]u8 = undefined;
    for (0..256) |i| {
        const c = @as(f32, i) / 255.0;
        const lin = if (c <= 0.04045)
            c / 12.92
        else
            std.math.pow(f32, (c + 0.055) / 1.055, 2.2);
        // Rescale to TIME_DITHER_STEPS
        tbl[i] = @intFromFloat(lin * TIME_DITHER_STEPS);
    }
    break :blk tbl;
};

const TIME_DITHER_STEPS = 16;
fn td_on(v: u8, t: usize) u1 {
    // return if ((v >> 5) > t) 1 else 0;
    //
    // return if (t % (255 / (v + 1)) == 0) 1 else 0;
    return if (gamma_lut[v] > t) 1 else 0;
}

fn temporal_dither(color: u32, t: u8) colors.RGB3 {
    const r8: u8 = @intCast((color >> 16) & 0xff);
    const g8: u8 = @intCast((color >> 8) & 0xff);
    const b8: u8 = @intCast((color >> 0) & 0xff);
    return colors.RGB3{ .r = td_on(r8, t), .g = td_on(g8, t), .b = td_on(b8, t) };
}

const buffer = @import("buffer.zig");
inline fn temporal_rgbbuf(buf: *buffer.Buffer, x: usize, y: usize, t: usize) colors.RGB3 {
    const color_rgb: u32 = buf[y][x];
    return temporal_dither(color_rgb, @intCast(t));
}

pub fn scanout(h: Hub75, b: *buffer.DoubleBuffer) void {
    b.lock();
    const fb = b.front();
    for (0..(TIME_DITHER_STEPS)) |t| {
        for (0..PACKED_ROWS) |r| {
            for (0..COLS) |c| {
                const x: u8 = @intCast(c);
                const y1: u8 = @intCast(r);
                const y2: u8 = y1 + 16;
                const p1 = temporal_rgbbuf(fb, x, y1, t);
                const p2 = temporal_rgbbuf(fb, x, y2, t);
                // write_packed_rgb(.{ .p1 = p1, .p2 = p2 });
                write_packed_rgb_fifo(.{ .p1 = p2, .p2 = p1 });
            }
            // time.sleep_us(1);
            // while (!rgb_pio.sm_is_rx_fifo_empty(rgb_statemachine)) {}

            // pins.led.toggle();
            write_addr(h, Addr.U32(r));
            h.pins.latch.put(0);
            //std.atomic.spinLoopHint();
            h.pins.latch.put(1);
            h.pins.output_enable.put(1);
            // time.sleep_us(1);
            // std.atomic.spinLoopHint();
            h.pins.output_enable.put(0);
        }
    }
    b.unlock();
}

pub fn scanout_forever(h: Hub75, b: *buffer.DoubleBuffer) void {
    var i: usize = 0;
    while (true) {
        const frame_start_time = hal.time.get_time_since_boot();
        scanout(h, b);
        const now = hal.time.get_time_since_boot();
        const frame_time = now.diff(frame_start_time);
        const scanout_fps = 1_000_000 / frame_time.to_us();
        i = i + 1;
        if (i > 10) {
            std.log.info("scanout FPS: {}", .{scanout_fps});
            i = 0;
        }
    }
}
