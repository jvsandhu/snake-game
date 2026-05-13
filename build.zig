const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (target.result.os.tag == .windows) {
        exe_mod.linkSystemLibrary("user32", .{});
        exe_mod.linkSystemLibrary("gdi32", .{});
    } else {
        @panic("This game only supports Windows. Use -Dtarget=x86_64-windows to cross-compile.");
    }

    const exe = b.addExecutable(.{
        .name = "snake",
        .root_module = exe_mod,
    });
    exe.subsystem = .Windows;
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the snake game");
    run_step.dependOn(&run_cmd.step);
}
