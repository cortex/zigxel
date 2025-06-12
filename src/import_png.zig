const std = @import("std");
const zigimg = @import("zigimg");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var image = try zigimg.Image.fromFilePath(allocator, "./src/font/font.png");
    defer image.deinit();
    const file = try std.fs.cwd().createFile(
        "src/font/font.bin",
        .{ .read = true },
    );
    defer file.close();

    // Write image.width
    var width_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &width_buf, @intCast(image.width), .little);
    try file.writeAll(&width_buf);

    // Write image.height
    var height_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &height_buf, @intCast(image.height), .little);
    try file.writeAll(&height_buf);

    for (0..image.width) |src_x| {
        for (0..image.height) |src_y| {
            std.log.info("x: {} y:{}", .{ src_x, src_y });
            const p = image.pixels.rgba32;
            const pixel = p[image.width * src_y + src_x];
            const rgb = pixel.to.u32Rgb(); // u32: 0x00RRGGBB
            var rgb_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &rgb_buf, rgb, .little);
            try file.writeAll(&rgb_buf);
        }
    }
}
