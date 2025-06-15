const microzig = @import("microzig");
const hal = microzig.hal;
const color = @import("color.zig");
const image = @import("image.zig");
const WIDTH = 64;
const HEIGHT = 32;

pub const Buffer = [HEIGHT][WIDTH]color.RGBA32;

pub const DoubleBuffer = struct {
    buffers: [2]Buffer = undefined,
    front_buffer_idx: u1 = 0,
    front_buffer_lock: hal.mutex.CoreMutex = hal.mutex.CoreMutex{},

    // Locks the buffer from being swapped
    pub fn lock(db: *DoubleBuffer) void {
        return db.front_buffer_lock.lock();
    }
    pub fn unlock(db: *DoubleBuffer) void {
        return db.front_buffer_lock.unlock();
    }
    pub fn swap(db: *DoubleBuffer) void {
        db.front_buffer_lock.lock();
        db.front_buffer_idx = ~db.front_buffer_idx;
        db.front_buffer_lock.unlock();
    }
    pub fn front(self: *DoubleBuffer) image.DynamicImage(color.RGBA32) {
        const front_ptr: *[HEIGHT][WIDTH]color.RGBA32 = &self.buffers[self.front_buffer_idx];

        // Get a pointer to the first element (i.e., front_ptr[0][0])
        const flat_ptr: [*]color.RGBA32 = @ptrCast(&front_ptr[0][0]);

        // Slice over the entire 2D buffer
        const flat: []color.RGBA32 = flat_ptr[0 .. WIDTH * HEIGHT];

        return image.DynamicImage(color.RGBA32){
            .width = WIDTH,
            .height = HEIGHT,
            .pixels = flat,
        };
    }

    pub fn back(self: *DoubleBuffer) image.DynamicImage(color.RGBA32) {
        const front_ptr: *[HEIGHT][WIDTH]color.RGBA32 = &self.buffers[~self.front_buffer_idx];

        // Get a pointer to the first element (i.e., front_ptr[0][0])
        const flat_ptr: [*]color.RGBA32 = @ptrCast(&front_ptr[0][0]);

        // Slice over the entire 2D buffer
        const flat: []color.RGBA32 = flat_ptr[0 .. WIDTH * HEIGHT];

        return image.DynamicImage(color.RGBA32){
            .width = WIDTH,
            .height = HEIGHT,
            .pixels = flat,
        };
    }
};
