const std = @import("std");
const zigimg = @import("zigimg");

fn convert(src_path: []const u8, target_path: []const u8) !void {
    const allocator = std.heap.page_allocator;
    var image = try zigimg.Image.fromFilePath(allocator, src_path);
    defer image.deinit();
    const file = try std.fs.cwd().createFile(
        target_path,
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

    if (image.pixelFormat() != .rgba32) {
        try image.convert(.rgba32);
    }

    for (0..image.width) |src_x| {
        for (0..image.height) |src_y| {
            const p = image.pixels.rgba32;
            const pixel = p[image.width * src_y + src_x];
            const rgb = pixel.to.u32Rgb(); // u32: 0x00RRGGBB
            var rgb_buf: [4]u8 = undefined;
            std.mem.writeInt(u32, &rgb_buf, rgb, .little);
            try file.writeAll(&rgb_buf);
        }
    }
}

pub fn main() !void {
    const alloc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        std.log.err("Usage: {s} <asset_dir> ", .{args[0]});
        return error.InvalidArguments;
    }
    const dir_path = args[1];
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    var dir_iter = dir.iterate();
    defer dir.close();

    while (try dir_iter.next()) |entry| {
        if (entry.kind == .file and
            std.mem.eql(u8, std.fs.path.extension(entry.name), ".png"))
        {
            const out = try std.mem.concat(
                std.heap.page_allocator,
                u8,
                &.{ std.fs.path.stem(entry.name), ".bin" },
            );
            const in_path = try std.fs.path.join(alloc, &.{ dir_path, entry.name });
            const out_path = try std.fs.path.join(alloc, &.{ dir_path, out });
            try convert(in_path, out_path);
            std.log.info("wrote {s}", .{out_path});
        }
    }
}
