const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const time = rp2xxx.time;

const hub75 = @import("hub75.zig");
const buffer = @import("buffer.zig");

var screen_buffer = buffer.DoubleBuffer{};
//
// Compile-time pin configuration
const pin_config = rp2xxx.pins.GlobalConfiguration{
    .GPIO25 = .{
        .name = "led",
        .direction = .out,
    },
    .GPIO6 = .{
        .name = "a",
        .direction = .out,
    },
    .GPIO7 = .{
        .name = "b",
        .direction = .out,
    },
    .GPIO8 = .{
        .name = "c",
        .direction = .out,
    },
    .GPIO9 = .{
        .name = "d",
        .direction = .out,
    },
    .GPIO10 = .{
        .name = "clk",
        .direction = .out,
    },
    .GPIO11 = .{
        .name = "latch",
        .direction = .out,
    },
    .GPIO12 = .{
        .name = "oen",
        .direction = .out,
    },
    .GPIO13 = .{
        .name = "redled",
        .direction = .out,
    },
};

const pins = pin_config.pins();
const colors = @import("color.zig");

fn pack2rgb(p1: u3, p2: u3) u6 {
    return @as(u6, @intCast(p1)) << 3 | p2;
}

pub fn render_rgb(db: *buffer.DoubleBuffer) void {
    const back_buffer = db.back();
    const t: u32 = @intCast(time.get_time_since_boot().to_us() / 1_00_00 % 8192);
    render_ff_img(back_buffer, font_ff, 0, 0, (t >> 3) % 64, 0);
    db.swap();
}

const font_ff = @embedFile("font/babe.ff");
fn rgb(r: u8, g: u8, b: u8) u32 {
    const r32: u32 = r;
    const g32: u32 = g;
    const b32: u32 = b;

    return r32 << 16 | g32 << 8 | b32;
}

fn render_ff_img(
    dest: *buffer.Buffer,
    ff_image: []const u8,
    dest_x: u32,
    dest_y: u32,
    src_offset_x: u32,
    src_offset_y: u32,
) void {
    const src_width = std.mem.readInt(u32, ff_image[8..12], .big);
    const src_height = std.mem.readInt(u32, ff_image[12..16], .big);
    const img_data = ff_image[16..];
    // if (true) {
    //     return;
    // }
    const width = if ((dest_x + src_width) > hub75.COLS) hub75.COLS else src_width;
    const height = if ((dest_y + src_height) > hub75.ROWS) hub75.ROWS else src_height;
    for (0..width) |out_x| {
        for (0..height) |out_y| {
            const src_x = out_x - src_offset_x;
            const src_y = out_y - src_offset_y;
            const color_offset = 8 * (src_width * src_height - ((src_width * src_y) + src_x));
            const color_data = img_data[color_offset..(color_offset + 8)];
            const r: u8 = @intCast(std.mem.readInt(u16, color_data[0..2], .big) >> 8);
            const g: u8 = @intCast(std.mem.readInt(u16, color_data[2..4], .big) >> 8);
            const b: u8 = @intCast(std.mem.readInt(u16, color_data[4..6], .big) >> 8);
            const a: u8 = @intCast(std.mem.readInt(u16, color_data[6..8], .big) >> 8);
            _ = a;
            dest[dest_y + out_y][dest_x + out_x] = rgb(r, g, b);
        }
    }
}

// Build RGB from 0..1 floats
fn rgbf(r: f32, g: f32, b: f32) u32 {
    const r8: u8 = @intFromFloat(r * 255);
    const g8: u8 = @intFromFloat(g * 255);
    const b8: u8 = @intFromFloat(b * 255);
    // convert to 32-bit RGB
    return @as(u32, r8) << 16 | @as(u32, g8) << 8 | @as(u32, b8);
}

const gpio = rp2xxx.gpio;
const uart = rp2xxx.uart.instance.num(0);
const baud_rate = 115200;

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = rp2xxx.uart.logFn,
};

fn rgb_renderloop() void {
    while (true) {
        render_rgb(&screen_buffer);
    }
}
pub fn main() !void {
    const uart_tx_pin = gpio.num(16);
    uart_tx_pin.set_function(.uart);

    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });

    rp2xxx.uart.init_logger(uart);
    std.log.info("zigxel\n", .{});
    pin_config.apply();
    pins.redled.put(0);
    const h = hub75.Hub75{ .pins = .{
        .addr_a = pins.a,
        .addr_b = pins.b,
        .addr_c = pins.c,
        .addr_d = pins.d,
        .clk = pins.clk,
        .latch = pins.latch,
        .output_enable = pins.oen,
    } };
    h.init();
    rp2xxx.multicore.launch_core1(rgb_renderloop);
    hub75.scanout_forever(h, &screen_buffer);
}
