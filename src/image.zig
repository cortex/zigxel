pub fn DynamicImage(comptime T: type) type {
    return struct {
        width: usize,
        height: usize,
        pixels: []T,
        pub fn read(self: @This(), x: usize, y: usize) T {
            return self.pixels[y * self.width + x];
        }
        pub inline fn write(self: @This(), x: usize, y: usize, c: T) void {
            self.pixels[y * self.width + x] = c;
        }
    };
}

pub fn StaticImage(comptime T: type, comptime width: usize, comptime height: usize) type {
    return struct {
        width: usize = width,
        height: usize = height,
        pixels: [width * height]T = [_]T{0} ** (width * height),
        pub fn read(self: @This(), x: usize, y: usize) T {
            return self.pixels[y * self.width + x];
        }
        pub fn write(self: *@This(), x: usize, y: usize, c: T) void {
            self.pixels[y * self.width + x] = c;
        }
    };
}
