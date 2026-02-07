const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "moresampler2",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    if (target.result.os.tag != .windows) {
        exe.linkSystemLibrary("m");
    }

    exe.addIncludePath(.{ .path = "libs/libllsm" });
    exe.addIncludePath(.{ .path = "libs/ciglet" });
    exe.addIncludePath(.{ .path = "libs/libpyin" });
    exe.addIncludePath(.{ .path = "libs/libgvps" });
    exe.addIncludePath(.{ .path = "libs" });

    const c_flags = [_][]const u8{
        "-DFP_TYPE=float",
    };

    const c_sources = [_][]const u8{
        "libs/libgvps/gvps_sampled.c",
        "libs/libgvps/gvps_variable.c",
        "libs/libgvps/gvps_full.c",
        "libs/libgvps/gvps_obsrv.c",
        "libs/libpyin/pyin.c",
        "libs/libpyin/math-funcs.c",
        "libs/libpyin/matlabfunctions.c",
        "libs/libpyin/yin.c",
        "libs/libllsm/layer0.c",
        "libs/libllsm/container.c",
        "libs/libllsm/frame.c",
        "libs/libllsm/llsmutils.c",
        "libs/libllsm/llsmrt.c",
        "libs/libllsm/layer1.c",
        "libs/libllsm/coder.c",
        "libs/libllsm/dsputils.c",
        "libs/ciglet/fast_median.c",
        "libs/ciglet/ciglet.c",
        "libs/ciglet/fftsg_h.c",
    };

    exe.addCSourceFiles(.{
        .files = &c_sources,
        .flags = &c_flags,
    });

    b.installArtifact(exe);
}
