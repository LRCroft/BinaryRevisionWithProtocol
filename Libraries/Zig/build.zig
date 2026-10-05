const std = @import("std");

pub fn build(b: *std.Build) void {
    const lib = b.addStaticLibrary(.{
        .name = "vsn",
        .target = b.standardTargetOptions(),
        .optimize = b.standardOptimizeOption(),
    });
    _ = lib;
}
