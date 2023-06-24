const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "tm1637",
        .root_source_file = .{ .path = "src/Tm1637.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // lib.linkSystemLibrary("libgpiod");
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/Tm1637.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const run_main_tests = b.addRunArtifact(main_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);

    const demo = b.addExecutable(std.Build.ExecutableOptions{
        .root_source_file = .{ .path = "src/demo.zig" },
        .target = target,
        .optimize = optimize,
        .name = "demo",
    });
    demo.linkLibrary(lib);
    b.installArtifact(demo);

    const demo_step = b.step("demo", "Build a demo program");
    demo_step.dependOn(&demo.step);
}
