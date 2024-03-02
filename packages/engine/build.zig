const std = @import("std");
const builtin = @import("builtin");

const blipbuf = @import("external/blip-buf/build.zig");
const raylib = @import("external/raylib/src/build.zig");
const mpack = @import("external/mpack/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const blip = blipbuf.addBlipBuf(b, target, .ReleaseFast);
    b.installArtifact(blip);

    const pack = mpack.addMPack(b, target, .ReleaseFast);
    b.installArtifact(pack);

    const ray = try raylib.addRaylib(b, target, .ReleaseFast, .{ .rmodels = false });
    ray.installHeader("external/raylib/src/raylib.h", "raylib.h");
    ray.installHeader("external/raylib/src/external/miniaudio.h", "miniaudio.h");
    b.installArtifact(ray);

    if (target.result.os.tag == .emscripten) {
        const wasm = b.addStaticLibrary(.{
            .name = "retrobob",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        if (b.sysroot) |sysroot| {
            const cache_include = try std.fs.path.join(b.allocator, &.{ sysroot, "cache", "sysroot", "include" });
            defer b.allocator.free(cache_include);
            wasm.addIncludePath(.{ .path = cache_include });
        }

        wasm.linkLibrary(blip);
        wasm.linkLibrary(pack);
        wasm.linkLibrary(ray);

        b.installArtifact(wasm);
    } else {
        const exe = b.addExecutable(.{
            .name = "retrobob",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        exe.linkLibrary(blip);
        exe.linkLibrary(pack);
        exe.linkLibrary(ray);

        if (target.result.os.tag == .windows and optimize != .Debug) {
            exe.addObjectFile(.{ .path = "src/assets/icon.rc.o" });
            exe.subsystem = .Windows;
        }

        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.linkLibrary(blip);
    unit_tests.linkLibrary(pack);
    unit_tests.linkLibrary(ray);

    const test_step = b.step("test", "Run unit tests");
    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);

    const debug_unit_tests = b.addInstallArtifact(unit_tests, .{});
    const debug_step = b.step("debug", "Prepare for debug");
    debug_step.dependOn(&debug_unit_tests.step);
}
