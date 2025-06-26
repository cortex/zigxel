const std = @import("std");
const color = @import("color.zig");
const image = @import("image.zig");
const hal = @import("microzig").hal;

pub var screen_buffer = DoubleBuffer{};
const WIDTH = 64;
const HEIGHT = 32;

pub const Buffer = [HEIGHT][WIDTH]color.RGBA32;

pub const DoubleBuffer = struct {
    buffers: [2]Buffer = undefined,
    front_buffer_idx: u1 = 0,
    front_buffer_lock: hal.mutex.CoreMutex = hal.mutex.CoreMutex{},

    // Locks the buffer from being swapped
    pub fn lock(db: *DoubleBuffer) void {
        return db.front_buffer_lock.lock();
    }
    pub fn unlock(db: *DoubleBuffer) void {
        return db.front_buffer_lock.unlock();
    }
    pub fn swap(db: *DoubleBuffer) void {
        db.front_buffer_lock.lock();
        prepare_scanout(db.front());
        db.front_buffer_idx = ~db.front_buffer_idx;
        db.front_buffer_lock.unlock();
    }
    pub fn front(self: *DoubleBuffer) image.DynamicImage(color.RGBA32) {
        const front_ptr: *[HEIGHT][WIDTH]color.RGBA32 = &self.buffers[self.front_buffer_idx];

        // Get a pointer to the first element (i.e., front_ptr[0][0])
        const flat_ptr: [*]color.RGBA32 = @ptrCast(&front_ptr[0][0]);

        // Slice over the entire 2D buffer
        const flat: []color.RGBA32 = flat_ptr[0 .. WIDTH * HEIGHT];

        return image.DynamicImage(color.RGBA32){
            .width = WIDTH,
            .height = HEIGHT,
            .pixels = flat,
        };
    }

    pub fn back(self: *DoubleBuffer) image.DynamicImage(color.RGBA32) {
        const front_ptr: *[HEIGHT][WIDTH]color.RGBA32 = &self.buffers[~self.front_buffer_idx];

        // Get a pointer to the first element (i.e., front_ptr[0][0])
        const flat_ptr: [*]color.RGBA32 = @ptrCast(&front_ptr[0][0]);

        // Slice over the entire 2D buffer
        const flat: []color.RGBA32 = flat_ptr[0 .. WIDTH * HEIGHT];

        return image.DynamicImage(color.RGBA32){
            .width = WIDTH,
            .height = HEIGHT,
            .pixels = flat,
        };
    }
};

pub fn init() void {
    init_rgb_pio();
    init_latch_addr_pio();
}

const rgb_pio: hal.pio.Pio = hal.pio.num(0);
const rgb_statemachine: hal.pio.StateMachine = .sm0;

const put_rgb_program = blk: {
    @setEvalBranchQuota(8000);
    break :blk hal.pio.assemble(
        \\.program put_rgb
        \\.side_set 1
        \\ set pindirs 1 side 0
        \\ .wrap_target
        \\    out pins 6 side 0 [0]
        \\    nop side 1 [1]
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
        .pin_mappings = .{
            .out = .{
                .base = 0,
                .count = 6,
            },
            .set = .{
                .base = 10,
                .count = 1,
            },
            .side_set = .{
                .base = 10,
                .count = 1,
            },
        },
        .shift = .{
            .out_shiftdir = .left,
        },
    }) catch unreachable;
    std.log.info("Initialized pio", .{});
    rgb_pio.sm_set_shift_options(rgb_statemachine, .{
        // .join_tx = true,
        .autopull = true,
        .pull_threshold = 24,
    });
    rgb_pio.sm_set_pindir(rgb_statemachine, 0, 6, .out);
    // rgb_pio.sm_set_pindir(rgb_statemachine, 10, 1, .out);
    rgb_pio.sm_set_enabled(rgb_statemachine, true);
}

inline fn write_packed_rgb_fifo(
    pp1: color.RGB2x3,
    pp2: color.RGB2x3,
    pp3: color.RGB2x3,
    pp4: color.RGB2x3,
) void {
    const p1: u32 = @intCast(@as(u6, @bitCast(pp1)));
    const p2: u32 = @intCast(@as(u6, @bitCast(pp2)));
    const p3: u32 = @intCast(@as(u6, @bitCast(pp3)));
    const p4: u32 = @intCast(@as(u6, @bitCast(pp4)));
    const pu32: u32 = (p4 << 18) | (p3 << 12) | (p2 << 6) | p1;
    rgb_pio.sm_write(rgb_statemachine, pu32);
}

const addr_payload = packed struct { addr: u4, sleep: u8, _padding: u20 = 0 };

inline fn write_addr_fifo(addr: u4, bitplane: u3) void {
    const t: u8 = 1;
    const sleep: u8 = t << (7 - bitplane);
    const payload = addr_payload{ .addr = ~addr, .sleep = sleep };
    latch_addr_pio.sm_write(latch_addr_statemachine, @bitCast(payload));
}

const latch_addr_program = blk: {
    @setEvalBranchQuota(8000);
    break :blk hal.pio.assemble(
        \\.program latch_addr
        \\ set pindirs 0b11
        \\ again:
        \\     pull block
        \\     out pins 4 [1]
        \\     set pins 0b11 [4]// Latch
        \\     set pins 0b10 [4]
        \\     set pins 0b00 [4] // OE
        \\     out x 3
        \\ sleep:
        \\     jmp x-- sleep [24] // Sleep according to bitplane
        \\     set pins 0b10 [1]
        \\     push 1
        \\     jmp again
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
            .clkdiv = hal.pio.ClkDivOptions.from_float(16),
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
        .join_tx = false,
    });
    latch_addr_pio.sm_set_pindir(latch_addr_statemachine, 6, 4, .out);
    latch_addr_pio.sm_set_enabled(latch_addr_statemachine, true);
}

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
        tbl[i] = @intFromFloat(lin * 255);
    }
    break :blk tbl;
};

const BITPLANES = 8;

inline fn bitplane_color(c: color.RGBA32, bitplane: u3) color.RGB3 {
    const bp_inv: u3 = @intCast(7 - bitplane);
    return color.RGB3{
        .r = @intCast((gamma_lut[c.r] >> bp_inv) & 1),
        .g = @intCast((gamma_lut[c.g] >> bp_inv) & 1),
        .b = @intCast((gamma_lut[c.b] >> bp_inv) & 1),
    };
}
test "gamma lut" {
    const result = gamma_lut[255];
    const expected: u8 = 255;
    std.debug.print("{b} {b}\n", .{ expected, result });
    return std.testing.expectEqual(expected, result);
}

test "bitplane_color" {
    const c = color.RGBA32{ .r = 255, .g = 0, .b = 0, .a = 0 };
    const bp = 1;
    const expected: u3 = @bitCast(color.RGB3{ .r = 1, .g = 0, .b = 0 });
    const result: u3 = @bitCast(bitplane_color(c, bp));
    std.debug.print("{b} {b}\n", .{ expected, result });
    return std.testing.expectEqual(result, expected);
}

const pt = @import("perf_timer.zig");
pub var fps_timer: pt.PerfTimer = undefined;
pub var prep_timer: pt.PerfTimer = undefined;
pub var addr_timer: pt.PerfTimer = undefined;
pub var scanout_timer: pt.PerfTimer = undefined;

const PACKED_ROWS = HEIGHT >> 1;

var scanout_buffer: [BITPLANES][PACKED_ROWS][WIDTH]color.RGB2x3 = undefined;

pub fn prepare_scanout(fb: image.DynamicImage(color.RGBA32)) void {
    prep_timer.start();
    for (0..BITPLANES) |bitplane_usize| {
        const bitplane: u3 = @intCast(bitplane_usize);
        for (0..PACKED_ROWS) |y| {
            for (0..WIDTH) |x| {
                const p1 = fb.read(x, y);
                const p2 = fb.read(x, y + 16);
                const bp1 = bitplane_color(p1, bitplane);
                const bp2 = bitplane_color(p2, bitplane);
                const d = color.RGB2x3{ .p1 = bp2, .p2 = bp1 };
                scanout_buffer[bitplane][y][x] = d;
            }
        }
    }
    prep_timer.lap();
}

pub fn scanout(_: *DoubleBuffer) void {
    for (0..BITPLANES) |bitplane_usize| {
        const bitplane: u3 = @intCast(bitplane_usize);
        for (0..PACKED_ROWS) |row_usize| {
            const row: u4 = @intCast(row_usize);
            scanout_timer.start();
            for (0..(WIDTH / 4)) |c| {
                write_packed_rgb_fifo(
                    scanout_buffer[bitplane][row][4 * c],
                    scanout_buffer[bitplane][row][4 * c + 1],
                    scanout_buffer[bitplane][row][4 * c + 2],
                    scanout_buffer[bitplane][row][4 * c + 3],
                );
            }
            scanout_timer.lap();
            addr_timer.start();
            write_addr_fifo(row, bitplane);
            _ = latch_addr_pio.sm_blocking_read(latch_addr_statemachine);
            addr_timer.lap();
        }
    }
}

pub fn scanout_forever() void {
    fps_timer.reset();
    while (true) {
        scanout(&screen_buffer);
        fps_timer.lap();
    }
}
