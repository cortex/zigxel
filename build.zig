const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});

pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});

    const mb = MicroBuild.init(b, mz_dep) orelse return;

    const firmware = mb.add_firmware(.{
        .name = "zigxel",
        .target = mb.ports.rp2xxx.boards.raspberrypi.pico,
        .optimize = .ReleaseSmall,
        .root_source_file = b.path("src/main.zig"),
    });
    mb.install_firmware(firmware, .{});

    const picotool_flash = b.addSystemCommand(&.{"sudo"});

    picotool_flash.addArg("picotool");
    picotool_flash.addArg("load");
    picotool_flash.addArg("zig-out/firmware/zigxel.uf2");

    const picotool_boot = b.addSystemCommand(&.{"sudo"});
    picotool_boot.addArg("picotool");
    picotool_boot.addArg("reboot");

    picotool_boot.step.dependOn(&picotool_flash.step);
    const flashStep = b.step("flash", "Flash the application");

    flashStep.dependOn(&firmware.artifact.step);
    flashStep.dependOn(&picotool_boot.step);

    // flashStep.dependOn(mb);
}
