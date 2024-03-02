const std = @import("std");

pub fn addMPack(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const lib = b.addStaticLibrary(.{
        .name = "mpack",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib.installHeader(srcdir ++ "/mpack.h", "mpack.h");
    lib.installHeader(srcdir ++ "/mpack-common.h", "mpack-common.h");
    lib.installHeader(srcdir ++ "/mpack-expect.h", "mpack-expect.h");
    lib.installHeader(srcdir ++ "/mpack-node.h", "mpack-node.h");
    lib.installHeader(srcdir ++ "/mpack-platform.h", "mpack-platform.h");
    lib.installHeader(srcdir ++ "/mpack-reader.h", "mpack-reader.h");
    lib.installHeader(srcdir ++ "/mpack-writer.h", "mpack-writer.h");

    const files: []const []const u8 = &.{
        srcdir ++ "/mpack-common.c",
        srcdir ++ "/mpack-expect.c",
        srcdir ++ "/mpack-node.c",
        srcdir ++ "/mpack-platform.c",
        srcdir ++ "/mpack-reader.c",
        srcdir ++ "/mpack-writer.c",
    };

    for (files) |file| {
        lib.addCSourceFile(.{ .file = .{ .path = file } });
    }

    if (target.result.os.tag == .emscripten) {
        if (b.sysroot == null) {
            @panic("Pass '--sysroot \"$EMSDK/upstream/emscripten\"'");
        }

        const cache_include = std.fs.path.join(b.allocator, &.{ b.sysroot.?, "cache", "sysroot", "include" }) catch @panic("Out of memory");
        defer b.allocator.free(cache_include);

        var dir = std.fs.openDirAbsolute(cache_include, std.fs.Dir.OpenDirOptions{ .access_sub_paths = true, .no_follow = true }) catch @panic("No emscripten cache. Generate it!");
        dir.close();

        lib.addIncludePath(.{ .path = cache_include });
    }

    return lib;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const lib = addMPack(b, target, optimize);
    b.installArtifact(lib);
}

const srcdir = struct {
    fn getSrcDir() []const u8 {
        return std.fs.path.dirname(@src().file).?;
    }
}.getSrcDir();
