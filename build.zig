const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const core = b.addModule("lightjs", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .pic = true,
    });
    const library = b.addLibrary(.{ .name = "lightjs", .linkage = .static, .root_module = core });
    library.bundle_compiler_rt = true;
    b.installArtifact(library);
    b.installFile("include/lightjs.h", "include/lightjs.h");

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/value.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "lightjs", .module = core }},
    }) });
    const test_step = b.step("test", "Run Zig and C checks");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const c_test = b.addExecutable(.{ .name = "abi-c", .root_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }) });
    c_test.root_module.addCSourceFile(.{ .file = b.path("tests/abi.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
    c_test.root_module.addIncludePath(b.path("include"));
    c_test.root_module.linkLibrary(library);
    test_step.dependOn(&b.addRunArtifact(c_test).step);

    const host_library = b.addLibrary(.{ .name = "lightjs-host", .linkage = .static, .root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .pic = true,
    }) });
    host_library.bundle_compiler_rt = true;
    const rust = b.addSystemCommand(&.{ "rustc", "--edition=2024", "--test" });
    rust.addFileArg(b.path("tests/abi.rs"));
    rust.addPrefixedFileArg("-Clink-arg=", host_library.getEmittedBin());
    rust.addArg("-o");
    const rust_binary = rust.addOutputFileArg("abi-rust");
    const rust_run = std.Build.Step.Run.create(b, "run Rust ABI checks");
    rust_run.addFileArg(rust_binary);
    b.step("test-rust", "Run Rust ABI checks on the host").dependOn(&rust_run.step);
}
