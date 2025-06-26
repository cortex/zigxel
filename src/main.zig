const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const hub75 = @import("hub75.zig");

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = rp2xxx.uart.log,
};

// Compile-time pin configuration
const pin_config = rp2xxx.pins.GlobalConfiguration{
    .GPIO25 = .{
        .name = "led",
        .direction = .out,
    },
    .GPIO13 = .{
        .name = "redled",
        .direction = .out,
    },
};

const pins = pin_config.pins();
const color = @import("color.zig");
const image = @import("image.zig");

const draw = @import("draw.zig");
var fire = draw.Fire.init();

const font = @import("font.zig");
pub fn scene(db: *hub75.DoubleBuffer) void {
    const back_buffer = db.back();
    const t: u32 = @intCast(time.get_time_since_boot().to_us() / 1_000 / 20);
    // render_ff_img(back_buffer, font_ff, 0, 0, (t >> 3) % 64, 0);
    // draw.draw_clear(back_buffer, color.RED);
    // const v: u8 = @intCast(t % 255);
    const v = 32;
    // std.log.info("Time: {} V: {}", .{ t, v });
    draw.draw_clear(back_buffer, color.RGBA32{ .r = v, .g = v, .b = v, .a = 0 });
    // fire.step();
    draw.draw_rainbow(back_buffer, t);
    if (t % 4 == 0) {
        fire.step();
    }
    // s
    // draw.draw_with_func(back_buffer, t, draw.gradient_draw);
    const toff = (t / 3) % 32;
    fire.draw(back_buffer);
    font.draw_string(back_buffer, "ZIG'", 40 - toff, 0);
    font.draw_string(back_buffer, " ♥ ", 50 - toff + 0, 0);
    font.draw_string(back_buffer, "Pico", 60 - toff + 0, 0);
    font.draw_string(back_buffer, " 🙂 ", 70 - toff + 0, 0);
    // font.draw_letter(back_buffer, 'S', t % 64, 0);
    // font.draw_letter(back_buffer, 'A', t % 64, 6);
    // font.draw_letter(back_buffer, 'R', t % 64, 12);
    // font.draw_letter(back_buffer, 'A', t % 64, 18);
    // font.draw_letter(back_buffer, '♥', 8 + t % 64, 8);

    // font.draw_letter(back_buffer, 'J', 16 + t % 64, 0);
    // font.draw_letter(back_buffer, 'O', 16 + t % 64, 6);
    // font.draw_letter(back_buffer, 'A', 16 + t % 64, 12);
    // font.draw_letter(back_buffer, 'K', 24 + t % 64, 0);
    // font.draw_letter(back_buffer, 'I', 24 + t % 64, 6);
    // font.draw_letter(back_buffer, 'M', 24 + t % 64, 12);
    db.swap();
}

const gpio = rp2xxx.gpio;
const uart = rp2xxx.uart.instance.num(0);
const baud_rate = 115200;

pub fn panic(
    message: []const u8,
    _: ?*std.builtin.StackTrace,
    _: ?usize,
) noreturn {
    pins.redled.put(1);
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

fn rgb_renderloop() void {
    var t = rp2xxx.time.get_time_since_boot();
    while (true) {
        scene(&hub75.screen_buffer);
        var nt = rp2xxx.time.get_time_since_boot();
        if (nt.diff(t).to_us() > 1_000_000) {
            std.log.info("fps: {} prep: {} addr: {} scanout: {}", .{
                hub75.fps_timer.avg_rate_s(),
                hub75.prep_timer.avg_duration_us(),
                hub75.addr_timer.avg_duration_us(),
                hub75.scanout_timer.avg_duration_us(),
            });
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
    pins.redled.put(0);
    font.init_font();
    hub75.init();
    rp2xxx.multicore.launch_core1(rgb_renderloop);
    hub75.scanout_forever();
}
