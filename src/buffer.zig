const microzig = @import("microzig");
const hal = microzig.hal;

const WIDTH = 64;
const HEIGHT = 32;

pub const Buffer = [HEIGHT][WIDTH]u32;

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
    pub fn front(db: *DoubleBuffer) *Buffer {
        return &db.buffers[db.front_buffer_idx];
    }
    pub fn back(db: *DoubleBuffer) *Buffer {
        return &db.buffers[~db.front_buffer_idx];
    }
};
