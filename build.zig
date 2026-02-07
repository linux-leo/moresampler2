const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- C library compile flags ---
    const c_flags: []const []const u8 = &.{
        "-DFP_TYPE=float",
        "-std=c99",
        "-fPIC",
        "-w", // suppress warnings from vendored C code
    };

    // --- libgvps (static) ---
    const gvps = b.addStaticLibrary(.{
        .name = "gvps",
        .target = target,
        .optimize = optimize,
    });
    gvps.addCSourceFiles(.{
        .files = &.{
            "libs/libgvps/gvps_full.c",
            "libs/libgvps/gvps_obsrv.c",
            "libs/libgvps/gvps_sampled.c",
            "libs/libgvps/gvps_variable.c",
        },
        .flags = c_flags,
    });
    gvps.addIncludePath(b.path("libs/libgvps"));
    gvps.linkLibC();

    // --- libpyin (static) ---
    const pyin = b.addStaticLibrary(.{
        .name = "pyin",
        .target = target,
        .optimize = optimize,
    });
    pyin.addCSourceFiles(.{
        .files = &.{
            "libs/libpyin/pyin.c",
            "libs/libpyin/yin.c",
            "libs/libpyin/math-funcs.c",
            "libs/libpyin/matlabfunctions.c",
        },
        .flags = c_flags,
    });
    pyin.addIncludePath(b.path("libs/libpyin"));
    pyin.addIncludePath(b.path("libs/libgvps"));
    pyin.linkLibrary(gvps);
    pyin.linkLibC();

    // --- ciglet (static) ---
    const ciglet = b.addStaticLibrary(.{
        .name = "ciglet",
        .target = target,
        .optimize = optimize,
    });
    ciglet.addCSourceFiles(.{
        .files = &.{
            "libs/ciglet/ciglet.c",
            "libs/ciglet/fast_median.c",
            "libs/ciglet/wavfile.c",
            "libs/ciglet/fftsg_h.c",
        },
        .flags = c_flags,
    });
    ciglet.addIncludePath(b.path("libs/ciglet"));
    ciglet.linkLibC();

    // --- libllsm (static) ---
    const llsm = b.addStaticLibrary(.{
        .name = "llsm",
        .target = target,
        .optimize = optimize,
    });
    llsm.addCSourceFiles(.{
        .files = &.{
            "libs/libllsm/container.c",
            "libs/libllsm/frame.c",
            "libs/libllsm/dsputils.c",
            "libs/libllsm/llsmutils.c",
            "libs/libllsm/layer0.c",
            "libs/libllsm/layer1.c",
            "libs/libllsm/coder.c",
            "libs/libllsm/llsmrt.c",
        },
        .flags = c_flags,
    });
    llsm.addIncludePath(b.path("libs/libllsm"));
    llsm.addIncludePath(b.path("libs"));
    llsm.addIncludePath(b.path("libs/ciglet"));
    llsm.linkLibrary(ciglet);
    llsm.linkLibC();

    // --- Main Zig executable ---
    const exe = b.addExecutable(.{
        .name = "moresampler2",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add C include paths so @cImport works
    exe.addIncludePath(b.path("libs/libllsm"));
    exe.addIncludePath(b.path("libs/ciglet"));
    exe.addIncludePath(b.path("libs/libpyin"));
    exe.addIncludePath(b.path("libs/libgvps"));
    exe.addIncludePath(b.path("libs"));

    // Link all C libraries
    exe.linkLibrary(llsm);
    exe.linkLibrary(ciglet);
    exe.linkLibrary(pyin);
    exe.linkLibrary(gvps);
    exe.linkLibC();

    b.installArtifact(exe);

    // --- Run step ---
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run moresampler2");
    run_step.dependOn(&run_cmd.step);

    // --- Tests ---
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.addIncludePath(b.path("libs/libllsm"));
    unit_tests.addIncludePath(b.path("libs/ciglet"));
    unit_tests.addIncludePath(b.path("libs/libpyin"));
    unit_tests.addIncludePath(b.path("libs/libgvps"));
    unit_tests.addIncludePath(b.path("libs"));
    unit_tests.linkLibrary(llsm);
    unit_tests.linkLibrary(ciglet);
    unit_tests.linkLibrary(pyin);
    unit_tests.linkLibrary(gvps);
    unit_tests.linkLibC();

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
