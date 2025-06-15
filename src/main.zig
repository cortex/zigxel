const std = @import("std");
const microzig = @import("microzig");
const rp2xxx = microzig.hal;
const time = rp2xxx.time;
const hub75 = @import("hub75.zig");
const buffer = @import("buffer.zig");

pub const microzig_options = microzig.Options{
    .log_level = .debug,
    .logFn = rp2xxx.uart.logFn,
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

pub fn scene(db: *buffer.DoubleBuffer) void {
    const back_buffer = db.back();
    const t: u32 = @intCast(time.get_time_since_boot().to_us() / 1_000 / 20);
    // render_ff_img(back_buffer, font_ff, 0, 0, (t >> 3) % 64, 0);
    // draw_rainbow(back_buffer, t);
    draw.draw_clear(back_buffer, color.BLACK);
    // fire.step();
    if (t % 4 == 0) {
        fire.step();
    }
    fire.draw(back_buffer);
    font.draw_letter(back_buffer, 'S', t % 64, 0);
    font.draw_letter(back_buffer, 'A', t % 64, 6);
    font.draw_letter(back_buffer, 'R', t % 64, 12);
    font.draw_letter(back_buffer, 'A', t % 64, 18);
    font.draw_letter(back_buffer, '♥', 8 + t % 64, 8);

    font.draw_letter(back_buffer, 'J', 16 + t % 64, 0);
    font.draw_letter(back_buffer, 'O', 16 + t % 64, 6);
    font.draw_letter(back_buffer, 'A', 16 + t % 64, 12);
    font.draw_letter(back_buffer, 'K', 24 + t % 64, 0);
    font.draw_letter(back_buffer, 'I', 24 + t % 64, 6);
    font.draw_letter(back_buffer, 'M', 24 + t % 64, 12);
    db.swap();
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
        scene(&hub75.screen_buffer);
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
    pins.redled.put(0);
    var h = hub75.Hub75{};
    font.init_font();
    h.init();
    rp2xxx.multicore.launch_core1(rgb_renderloop);
    hub75.scanout_forever(h);
}
