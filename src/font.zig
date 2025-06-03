const std = @import("std");

const font_ff = @embedFile("font/font.ff");

pub fn main() void {
    const width = std.mem.readInt(u32, font_ff[8..12], .big);
    const height = std.mem.readInt(u32, font_ff[12..16], .big);
    const img_data = font_ff[16..];
    std.debug.print("width: {} height:{}\n", .{ width, height });
    for (0..width) |src_x| {
        for (0..height) |src_y| {
            const color_offset = 8 * (width * src_y + src_x);
            const color_data = img_data[color_offset..(color_offset + 8)];
            const r: u16 = @intCast(std.mem.readInt(u16, color_data[0..2], .big));
            const g: u16 = @intCast(std.mem.readInt(u16, color_data[2..4], .big));
            const b: u16 = @intCast(std.mem.readInt(u16, color_data[4..6], .big));
            const a: u16 = @intCast(std.mem.readInt(u16, color_data[6..8], .big));
            _ = a;
            // buffer[buf_y + src_y][buf_x + src_x] = rgb(128, 128, 128);
            //buffer[buf_y + src_y][buf_x + src_x] = rgb(r, g, b);
            // buffer[buf_y + src_y][buf_x + src_x] = 0xffffff;
            std.debug.print("O: {} D: {x}", .{ color_offset, color_data });
            std.debug.print("X {} Y {} RGB {} {} {}\n", .{ src_x, src_y, r, g, b });
        }
    }

    //

}
