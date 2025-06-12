const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const time = rp2xxx.time;

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = rp2xxx.uart.logFn,
};

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
    const t: u32 = @intCast(time.get_time_since_boot().to_us() / 1_000 / 20);
    // render_ff_img(back_buffer, font_ff, 0, 0, (t >> 3) % 64, 0);
    draw_rainbow(back_buffer, t);
    // drawtext(back_buffer, "hej") catch |err| {
    //     std.log.info("error drawing image: {}", .{err});
    // };
    draw_letter(back_buffer, 'S', t % 64, 0);
    draw_letter(back_buffer, 'A', t % 64, 6);
    draw_letter(back_buffer, 'R', t % 64, 12);
    draw_letter(back_buffer, 'A', t % 64, 18);
    draw_letter(back_buffer, '♥', 8 + t % 64, 8);

    draw_letter(back_buffer, 'J', 16 + t % 64, 0);
    draw_letter(back_buffer, 'O', 16 + t % 64, 6);
    draw_letter(back_buffer, 'A', 16 + t % 64, 12);
    draw_letter(back_buffer, 'K', 24 + t % 64, 0);
    draw_letter(back_buffer, 'I', 24 + t % 64, 6);
    draw_letter(back_buffer, 'M', 24 + t % 64, 12);
    db.swap();
}

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

const font_bin = @embedFile("font/font.bin");
fn drawtext(dest: color.Image, _: []const u8) !void {
    const src_width = std.mem.readInt(u32, font_bin[0..4], .little);
    const src_height = std.mem.readInt(u32, font_bin[4..8], .little);
    const src_data = font_bin[8..];
    for (0..@min(dest.width, src_width)) |src_x| {
        for (0..@min(dest.height, src_height)) |src_y| {
            const ofs = 4 * (src_x * src_height + src_y);
            const pixel_data = std.mem.readInt(u32, src_data[ofs..(ofs + 4)][0..4], .little);
            const pixel: colors.RGBA32 = @bitCast(pixel_data);
            const c = colors.RGBA32{
                .r = pixel.r,
                .g = pixel.g,
                .b = pixel.b,
            };
            dest.write(src_x, src_y, c);
        }
    }
}

const fontmap = "1234567890ABCDEFGHIJKLMNOPQRSTUVXYZÅÄÖ♥";
fn find_letter_index(l: u21) ?usize {
    var view = std.unicode.Utf8View.init(fontmap) catch unreachable;
    var iterator = view.iterator();
    var i: u8 = 0;
    while (iterator.nextCodepoint()) |cp| {
        if (cp == l) {
            return i;
        }
        i = i + 1;
    }
    return null;
}

fn draw_letter(dest: colors.Image, letter: u21, x: usize, y: usize) void {
    const idx = find_letter_index(letter);
    // std.log.info("found letter {?} at {?}", .{ letter, idx });
    if (idx) |index| {
        draw_image(dest, font_sheet, x, y, .{
            .src_x = 8 * index,
            .src_y = 0,
            .w = 8,
            .h = 8,
        });
    }
}

const DrawOptions = struct {
    src_x: usize,
    src_y: usize,
    w: usize,
    h: usize,
};

fn draw_image(
    dest: colors.Image,
    src: colors.Image,
    x: usize,
    y: usize,
    opts: DrawOptions,
) void {
    for (0..opts.w) |w| {
        for (0..opts.h) |h| {
            const c = src.read(opts.src_x + w, opts.src_y + h);
            if ((x + h) < dest.width and (y + w) < dest.height) {
                if (c == colors.WHITE) {
                    dest.write(x + h, y + w, c);
                }
            }
        }
    }
}

var buf: [1024 * 10]u8 = undefined;
var font_sheet: colors.Image = undefined;
fn image_from_bin(img_bin: [*]const u8) !colors.Image {
    const src_width = std.mem.readInt(u32, img_bin[0..4], .little);
    const src_height = std.mem.readInt(u32, img_bin[4..8], .little);
    std.log.info("will allocate: {} {}", .{ src_width, src_height });
    const src_data = img_bin[8..];
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = fba.allocator();
    std.log.info("will allocate: {}", .{src_width * src_height * 4});
    const pixels: []colors.RGBA32 = try allocator.alloc(colors.RGBA32, src_width * src_height);

    for (0..src_width) |src_x| {
        for (0..src_height) |src_y| {
            const ofs = 4 * (src_x * src_height + src_y);
            const pixel_data = std.mem.readInt(u32, src_data[ofs..(ofs + 4)][0..4], .little);
            const pixel: colors.RGBA32 = @bitCast(pixel_data);
            const c = colors.RGBA32{
                .r = pixel.r,
                .g = pixel.g,
                .b = pixel.b,
            };
            pixels[src_y * src_width + src_x] = c;
        }
    }

    std.log.info("font loaded", .{});
    return colors.Image{
        .width = src_width,
        .height = src_height,
        .pixels = pixels,
    };
}

fn init_font() void {
    font_sheet = image_from_bin(font_bin) catch |err| {
        std.log.err("error in image: {}", .{err});
        return undefined;
    };
}

// const font_ff = @embedFile("font/babe.ff");
const color = @import("color.zig");
fn rgb(r: u8, g: u8, b: u8) color.RGBA32 {
    return color.RGBA32{ .a = 0, .r = r, .g = g, .b = b };
}

fn render_ff_img(
    dest: color.Image,
    ff_image: []const u8,
    dest_x: u32,
    dest_y: u32,
    src_offset_x: u32,
    src_offset_y: u32,
) void {
    const src_width = std.mem.readInt(u32, ff_image[8..12], .big);
    const src_height = std.mem.readInt(u32, ff_image[12..16], .big);
    const img_data = ff_image[16..];
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
            const c = colors.RGBA32{ .a = a, .r = r, .g = g, .b = b };
            dest.write(dest_x + out_x, dest_y + out_y, c);
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
    pins.redled.put(1);
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

fn rgb_renderloop() void {
    var t = rp2xxx.time.get_time_since_boot();
    var i: u32 = 0;
    while (true) {
        render_rgb(&screen_buffer);
        var nt = rp2xxx.time.get_time_since_boot();
        i = i + 1;
        if (nt.diff(t).to_us() > 1_000_000) {
            const render_fps: u32 = @intCast(i * 1_000_000 / nt.diff(t).to_us());
            std.log.info("Scanout FPS: {} Render FPS: {}", .{
                hub75.scanout_fps,
                render_fps,
            });
            i = 0;
            t = nt;
        }
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
    pins.redled.put(1);
    var h = hub75.Hub75{ .pins = .{
        .addr_a = gpio.num(6),
        .addr_b = gpio.num(7),
        .addr_c = gpio.num(8),
        .addr_d = gpio.num(9),
        .clk = pins.clk,
        .latch = pins.latch,
        .output_enable = pins.oen,
    } };
    init_font();
    h.init();
    rp2xxx.multicore.launch_core1(rgb_renderloop);
    hub75.scanout_forever(h, &screen_buffer);
}
