const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const time = rp2xxx.time;

// Compile-time pin configuration
const pin_config = rp2xxx.pins.GlobalConfiguration{ .GPIO25 = .{
    .name = "led",
    .direction = .out,
}, .GPIO0 = .{
    .name = "r0",
    .direction = .out,
}, .GPIO1 = .{
    .name = "g0",
    .direction = .out,
}, .GPIO2 = .{
    .name = "b0",
    .direction = .out,
}, .GPIO3 = .{
    .name = "r1",
    .direction = .out,
}, .GPIO4 = .{
    .name = "g1",
    .direction = .out,
}, .GPIO5 = .{
    .name = "b1",
    .direction = .out,
}, .GPIO6 = .{
    .name = "a",
    .direction = .out,
}, .GPIO7 = .{
    .name = "b",
    .direction = .out,
}, .GPIO8 = .{
    .name = "c",
    .direction = .out,
}, .GPIO9 = .{
    .name = "d",
    .direction = .out,
}, .GPIO10 = .{
    .name = "clk",
    .direction = .out,
}, .GPIO11 = .{
    .name = "latch",
    .direction = .out,
}, .GPIO12 = .{
    .name = "oen",
    .direction = .out,
} };

const pins = pin_config.pins();

// 1-bit RGB color
const RGB1 = packed struct {
    r: u1,
    g: u1,
    b: u1,
};

// Write RGB 2x and pulse clock
fn write_packed_rgb(pp: u6) void {
    pins.r0.put(@intCast(pp >> 2 & 1));
    pins.g0.put(@intCast(pp >> 1 & 1));
    pins.b0.put(@intCast(pp >> 0 & 1));
    pins.r1.put(@intCast(pp >> 5 & 1));
    pins.g1.put(@intCast(pp >> 4 & 1));
    pins.b1.put(@intCast(pp >> 3 & 1));
    pins.clk.put(1);
    std.atomic.spinLoopHint();
    // time.sleep_us(1);
    pins.clk.put(0);

    std.atomic.spinLoopHint();
    // time.sleep_us(1);
}

fn write_addr(addr: u4) void {
    pins.a.put(@intCast(~((addr >> 0) & 1)));
    pins.b.put(@intCast(~((addr >> 1) & 1)));
    pins.c.put(@intCast(~((addr >> 2) & 1)));
    pins.d.put(@intCast(~((addr >> 3) & 1)));
}

const ROWS: usize = 32;
const COLS: usize = 64;
const PACKED_ROWS = ROWS >> 1;

var framebuffer: [PACKED_ROWS * COLS]u6 = undefined;
var rgb_buffers: [2][ROWS][COLS]u32 = undefined;

var front_buffer: u1 = 0;
var front_buffer_lock = rp2xxx.mutex.CoreMutex{};

fn sine(x: u8, y: u8, t: u8) u3 {
    const ft: f32 = @floatFromInt(t);
    const nx: f32 = ft + 10.0 * (@as(f32, @floatFromInt(x)) / 64.0);
    const ny: f32 = @as(f32, @floatFromInt(y)) / 32.0;
    return if (ny - @sin(nx) < 0.1) 2 else 0;
}

fn sierp(x: u8, y: u8, _: u8) u3 {
    return if (x & y > 0) 4 else 0;
}

fn xanim(x: u8, _: u8, t: u8) u3 {
    return if (x == t % 64) 1 else 0;
}

fn yanim(_: u8, y: u8, t: u8) u3 {
    return if (y == t % 32) 1 else 0;
}

fn pack2rgb(p1: u3, p2: u3) u6 {
    return @as(u6, @intCast(p1)) << 3 | p2;
}

fn render() void {
    for (0..PACKED_ROWS) |i| {
        for (0..COLS) |j| {
            const x: u8 = @intCast(j);
            const y1: u8 = @intCast(i);
            const y2: u8 = y1 + 16;
            const t: u8 = @intCast(time.get_time_since_boot().to_us() / 1_000_000 % 255);
            const p1 = sine(x, y1, t);
            const p2 = sine(x, y2, t);
            framebuffer[i * PACKED_ROWS + j] = pack2rgb(p2, p1);
            // framebuffer[i * PACKED_ROWS + j] = 0b111111;
        }
    }
}

fn renderloop() void {
    while (true) {
        render();
    }
}

fn scanloop() void {
    while (true) {
        for (0..PACKED_ROWS) |r| {
            write_addr(@intCast(r));
            for (0..COLS) |c| {
                write_packed_rgb(framebuffer[r * PACKED_ROWS + c]);
            }
            pins.led.toggle();
            pins.latch.put(0);
            pins.latch.put(1);
            pins.oen.put(1);
            time.sleep_us(1);
            pins.oen.put(0);
        }
    }
}

const TIME_DITHER_STEPS = 8;
fn td_on(v: u8, t: usize) u1 {
    return if ((v >> 5) > t) 1 else 0;
    // return if (t % (255 / (v + 1)) == 0) 1 else 0;
}

fn temporal_dither(color: u32, t: u8) u3 {
    const r8: u8 = @intCast((color >> 16) & 0xff);
    const g8: u8 = @intCast((color >> 8) & 0xff);
    const b8: u8 = @intCast((color >> 0) & 0xff);
    const r1: u3 = td_on(r8, t);
    const g1: u3 = td_on(g8, t);
    const b1: u3 = td_on(b8, t);
    return ((r1 << 2) | (g1 << 1) | b1);
}

fn temporal_rgbbuf(buf_i: u8, x: usize, y: usize, t: usize) u3 {
    const color_rgb: u32 = rgb_buffers[buf_i][y][x];
    return temporal_dither(color_rgb, @intCast(t));
}

pub fn rgbloop() void {
    while (true) {
        front_buffer_lock.lock();
        const fb = front_buffer;
        for (0..(TIME_DITHER_STEPS)) |t| {
            for (0..PACKED_ROWS) |r| {
                for (0..COLS) |c| {
                    const x: u8 = @intCast(c);
                    const y1: u8 = @intCast(r);
                    const y2: u8 = y1 + 16;
                    const p1 = temporal_rgbbuf(fb, x, y1, t);
                    const p2 = temporal_rgbbuf(fb, x, y2, t);
                    write_packed_rgb(pack2rgb(p1, p2));
                }
                pins.led.toggle();
                write_addr(@intCast(r));
                pins.latch.put(0);
                std.atomic.spinLoopHint();
                pins.latch.put(1);
                pins.oen.put(1);
                // time.sleep_us(1);
                std.atomic.spinLoopHint();
                pins.oen.put(0);
            }
        }
        front_buffer_lock.unlock();
    }
}

pub fn render_rgb() void {
    const back_index: u1 = ~front_buffer;

    const t: u32 = @intCast(time.get_time_since_boot().to_us() / 1_0_000 % 255);
    const tf: f32 = @floatFromInt(t);
    for (0..ROWS) |y| {
        for (0..COLS) |x| {
            const xf: f32 = @floatFromInt(x);
            const yf: f32 = @floatFromInt(y);
            _ = xf;
            _ = yf;
            _ = tf;
            //rgb_buffer[4 * (y * COLS + x)] = @intCast(x * 2);
            //const r: u32 = @intFromFloat(0xff * ((tf + xf) / 64.0));

            //const b: u32 = @intFromFloat(0xff * ((tf + yf) / 32.0));
            //const b: u32 = 0;
            // rgb_buffers[back_index][y][x] = (r << 16) + b;
            rgb_buffers[back_index][y][x] = t * (x & y);
        }
    }

    render_ff_img(&rgb_buffers[back_index], font_ff, 0, 0, (t >> 3) % 64, 0);
    front_buffer_lock.lock();
    front_buffer = back_index;
    front_buffer_lock.unlock();
}

const font_ff = @embedFile("font/babe.ff");
fn rgb(r: u8, g: u8, b: u8) u32 {
    const r32: u32 = r;
    const g32: u32 = g;
    const b32: u32 = b;

    return r32 << 16 | g32 << 8 | b32;
}

fn render_ff_img(
    dest: *[ROWS][COLS]u32,
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
    const width = if ((dest_x + src_width) > COLS) COLS else src_width;
    const height = if ((dest_y + src_height) > ROWS) ROWS else src_height;
    for (0..width) |out_x| {
        for (0..height) |out_y| {
            const src_x = out_x - src_offset_x;
            const src_y = out_y - src_offset_y;
            const color_offset = 8 * (src_width * src_y + src_x);
            const color_data = img_data[color_offset..(color_offset + 8)];
            const r: u8 = @intCast(std.mem.readInt(u16, color_data[0..2], .big) >> 8);
            const g: u8 = @intCast(std.mem.readInt(u16, color_data[2..4], .big) >> 8);
            const b: u8 = @intCast(std.mem.readInt(u16, color_data[4..6], .big) >> 8);
            const a: u8 = @intCast(std.mem.readInt(u16, color_data[6..8], .big) >> 8);
            _ = a;
            // buffer[buf_y + src_y][buf_x + src_x] = rgb(128, 128, 128);
            dest[dest_y + out_y][dest_x + out_x] = rgb(r, g, b);
            // buffer[buf_y + src_y][buf_x + src_x] = 0xffffff;
        }
    }
}

fn rgb_renderloop() void {
    while (true) {
        render_rgb();
    }
}

pub fn main() !void {
    pin_config.apply();
    render_rgb();
    rp2xxx.multicore.launch_core1(rgb_renderloop);
    // scanloop();
    rgbloop();
}
