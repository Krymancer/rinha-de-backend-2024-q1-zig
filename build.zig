const std = @import("std");

const ModuleMap = std.StringArrayHashMap(*std.Build.Module);

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var modules = ModuleMap.init(allocator);
    defer modules.deinit();

    const dep_opts = .{ .target = target, .optimize = optimize };

    try modules.put("zul", b.dependency("zul", dep_opts).module("zul"));
    try modules.put("logz", b.dependency("logz", dep_opts).module("logz"));
    try modules.put("httpz", b.dependency("httpz", dep_opts).module("httpz"));
    try modules.put("cache", b.dependency("cache", dep_opts).module("cache"));
    try modules.put("buffer", b.dependency("buffer", dep_opts).module("buffer"));
    try modules.put("typed", b.dependency("typed", dep_opts).module("typed"));
    try modules.put("validate", b.dependency("validate", dep_opts).module("validate"));
    try modules.put("pg", b.dependency("pg", dep_opts).module("pg"));

    const exe = b.addExecutable(.{
        .name = "rinha-de-backend-2024-q1-zig",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    var it = modules.iterator();
    while (it.next()) |m| {
        exe.root_module.addImport(m.key_ptr.*, m.value_ptr.*);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
