const std = @import("std");
const microzig = @import("microzig");

const MicroBuild = microzig.MicroBuild(.{
    .rp2xxx = true,
});
pub fn build(b: *std.Build) void {
    const mz_dep = b.dependency("microzig", .{});

    const mb = MicroBuild.init(b, mz_dep) orelse return;
    const target = mb.ports.rp2xxx.boards.raspberrypi.pico;
    const optimize = std.builtin.OptimizeMode.ReleaseFast;

    const zigimg_dependency = b.dependency("zigimg", .{
        .optimize = optimize,
    });

    const firmware = mb.add_firmware(.{
        .name = "zigxel",
        .target = target,
        .optimize = .ReleaseFast,
        .root_source_file = b.path("src/main.zig"),
    });
    mb.install_firmware(firmware, .{});

    // firmware.add_app_import("zigimg", zigimg_dependency.module("zigimg"), .{});
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

    const exe = b.addExecutable(.{
        .name = "convert",
        .root_source_file = b.path("src/import_png.zig"),
        .target = b.graph.host,
    });
    exe.root_module.addImport("zigimg", zigimg_dependency.module("zigimg"));
    const run_image_import = b.addRunArtifact(exe);
    run_image_import.addArg("src/assets");
    const imageStep = b.step("convert", "convert images");
    imageStep.dependOn(&run_image_import.step);
}
