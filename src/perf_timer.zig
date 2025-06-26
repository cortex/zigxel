const std = @import("std");
const time = @import("microzig").drivers.time;
const hal = @import("microzig").hal;

const HalTimer = struct {
    previous: time.Absolute,
    fn init() @This() {
        return .{ .previous = hal.time.get_time_since_boot() };
    }
    fn reset(self: *HalTimer) void {
        self.previous = hal.time.get_time_since_boot();
    }
    fn lap(self: *HalTimer) time.Duration {
        const now = hal.time.get_time_since_boot();
        const duration = now.diff(self.previous);
        self.previous = now;
        return duration;
    }
};

pub const PerfTimer = struct {
    timer: HalTimer,
    total_duration: time.Duration,
    count: u32,

    pub fn init() @This() {
        return .{
            .timer = HalTimer.init(),
            .total_duration = time.Duration.from_us(0),
            .count = 0,
        };
    }
    // Reset everything
    pub fn reset(self: *@This()) void {
        self.timer.reset();
        self.total_duration = time.Duration.from_us(0);
        self.count = 0;
    }
    // Reset timer without restting total count and duration
    pub fn start(self: *@This()) void {
        self.timer.reset();
    }
    pub fn lap(self: *@This()) void {
        self.count += 1;
        self.total_duration = self.total_duration.plus(self.timer.lap());
    }

    pub fn avg_duration_s(self: @This()) u64 {
        return self.total_duration.to_us() * 1_000_000 / self.count;
    }

    pub fn avg_duration_us(self: @This()) u64 {
        return self.total_duration.to_us() / self.count;
    }

    pub fn avg_rate_s(self: @This()) u32 {
        const cps: u64 = self.count * 1_000_000 / self.total_duration.to_us();
        return @intCast(cps);
    }
};
