const std = @import("std");
const image = @import("image.zig");
const color = @import("color.zig");
const draw = @import("draw.zig");

const font_bin = @embedFile("assets/font.bin");

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

pub fn draw_letter(dest: image.DynamicImage(color.RGBA32), letter: u21, x: usize, y: usize) void {
    const idx = find_letter_index(letter);
    // std.log.info("found letter {?} at {?}", .{ letter, idx });
    if (idx) |index| {
        draw.draw_image(dest, font_sheet, x, y, .{
            .src_x = 8 * index,
            .src_y = 0,
            .w = 8,
            .h = 8,
        });
    }
}

var buf: [1024 * 10]u8 = undefined;
var font_sheet: image.DynamicImage(color.RGBA32) = undefined;
fn image_from_bin(img_bin: [*]const u8) !image.DynamicImage(color.RGBA32) {
    const src_width = std.mem.readInt(u32, img_bin[0..4], .little);
    const src_height = std.mem.readInt(u32, img_bin[4..8], .little);
    std.log.info("will allocate: {} {}", .{ src_width, src_height });
    const src_data = img_bin[8..];
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    var allocator = fba.allocator();
    std.log.info("will allocate: {}", .{src_width * src_height * 4});
    const pixels: []color.RGBA32 = try allocator.alloc(color.RGBA32, src_width * src_height);

    for (0..src_width) |src_x| {
        for (0..src_height) |src_y| {
            const ofs = 4 * (src_x * src_height + src_y);
            const pixel_data = std.mem.readInt(u32, src_data[ofs..(ofs + 4)][0..4], .little);
            const pixel: color.RGBA32 = @bitCast(pixel_data);
            const c = color.RGBA32{
                .r = pixel.r,
                .g = pixel.g,
                .b = pixel.b,
            };
            pixels[src_y * src_width + src_x] = c;
        }
    }

    std.log.info("font loaded", .{});
    return image.DynamicImage(color.RGBA32){
        .width = src_width,
        .height = src_height,
        .pixels = pixels,
    };
}

pub fn init_font() void {
    font_sheet = image_from_bin(font_bin) catch |err| {
        std.log.err("error in image: {}", .{err});
        return undefined;
    };
}
