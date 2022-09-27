const builtin = @import("builtin");
const std = @import("std");
const Builder = std.build.Builder;

// const system_sdk = @import("system_sdk.zig");

pub fn build(b: *Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&(try testStep(b, mode, target)).step);
    test_step.dependOn(&(try testStepShared(b, mode, target)).step);
}

pub fn testStep(b: *Builder, mode: std.builtin.Mode, target: std.zig.CrossTarget) !*std.build.RunStep {
    const main_tests = b.addTestExe("flac-tests", thisDir() ++ "/src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.setTarget(target);
    try link(b, main_tests, .{});
    main_tests.install();
    return main_tests.run();
}

fn testStepShared(b: *Builder, mode: std.builtin.Mode, target: std.zig.CrossTarget) !*std.build.RunStep {
    const main_tests = b.addTestExe("flac-tests-shared", thisDir() ++ "/src/main.zig");
    main_tests.setBuildMode(mode);
    main_tests.setTarget(target);
    try link(b, main_tests, .{ .shared = true });
    main_tests.install();
    return main_tests.run();
}

const Options = struct {
    shared: bool = false,
};

pub const pkg = std.build.Pkg{
    .name = "flac",
    .source = .{ .path = thisDir() ++ "/src/main.zig" },
};

pub const LinkError = error{FailedToLinkGPU} || BuildError;
pub fn link(b: *Builder, step: *std.build.LibExeObjStep, options: Options) LinkError!void {
    const lib = try buildLibrary(b, step.build_mode, step.target, options);
    step.linkLibrary(lib);
    addFLACIncludes(step);
    // if (options.shared) {
    //     step.defineCMacro("GLFW_DLL", null);
    //     system_sdk.include(b, step, options.system_sdk);
    // } else {
    linkFLACDependencies(b, step, options);
    // }
}

pub const BuildError = error{CannotEnsureDependency} || std.mem.Allocator.Error;
fn buildLibrary(b: *Builder, mode: std.builtin.Mode, target: std.zig.CrossTarget, options: Options) BuildError!*std.build.LibExeObjStep {
    // TODO(build-system): https://github.com/hexops/mach/issues/229#issuecomment-1100958939
    ensureDependencySubmodule(b.allocator, "upstream") catch return error.CannotEnsureDependency;

    const lib = if (options.shared)
        b.addSharedLibrary("flac", null, .{ .versioned = .{ .major = 12, .minor = 0, .patch = 0 } })
    else
        b.addStaticLibrary("flac", null);
    lib.setBuildMode(mode);
    lib.setTarget(target);

    // if (options.shared)
    //     lib.defineCMacro("_GLFW_BUILD_DLL", null);

    addFLACIncludes(lib);
    try addFLACSources(b, lib, options);
    linkFLACDependencies(b, lib, options);

    // if (options.install_libs)
    //     lib.install();

    return lib;
}

fn addFLACIncludes(step: *std.build.LibExeObjStep) void {
    step.addIncludePath(thisDir() ++ "/upstream/include");
}

fn addFLACSources(b: *Builder, lib: *std.build.LibExeObjStep, options: Options) std.mem.Allocator.Error!void {
    _ = options;
    const include_flac_src = "-I" ++ thisDir() ++ "/upstream/src/libFLAC/include/";
    switch (lib.target_info.target.os.tag) {
        // .windows => lib.addCSourceFiles(&.{
        //     thisDir() ++ "/src/sources_all.c",
        //     thisDir() ++ "/src/sources_windows.c",
        // }, &.{ "-D_FLAC_WIN32", include_flac_src }),
        else => {
            var sources = std.ArrayList([]const u8).init(b.allocator);
            var flags = std.ArrayList([]const u8).init(b.allocator);

            const include_src_dir = thisDir() ++ "/upstream/src/libFLAC/";
            try sources.append(include_src_dir ++ "bitmath.c");
            try sources.append(include_src_dir ++ "bitreader.c");
            try sources.append(include_src_dir ++ "bitwriter.c");
            try sources.append(include_src_dir ++ "cpu.c");
            try sources.append(include_src_dir ++ "crc.c");
            try sources.append(include_src_dir ++ "fixed.c");
            try sources.append(include_src_dir ++ "fixed_intrin_sse2.c");
            try sources.append(include_src_dir ++ "fixed_intrin_ssse3.c");
            try sources.append(include_src_dir ++ "float.c");
            try sources.append(include_src_dir ++ "format.c");
            try sources.append(include_src_dir ++ "lpc.c");
            try sources.append(include_src_dir ++ "lpc_intrin_avx2.c");
            try sources.append(include_src_dir ++ "lpc_intrin_fma.c");
            try sources.append(include_src_dir ++ "lpc_intrin_neon.c");
            try sources.append(include_src_dir ++ "lpc_intrin_sse2.c");
            try sources.append(include_src_dir ++ "lpc_intrin_sse41.c");
            try sources.append(include_src_dir ++ "lpc_intrin_vsx.c");
            try sources.append(include_src_dir ++ "md5.c");
            try sources.append(include_src_dir ++ "memory.c");
            try sources.append(include_src_dir ++ "metadata_iterators.c");
            try sources.append(include_src_dir ++ "metadata_object.c");
            try sources.append(include_src_dir ++ "stream_decoder.c");
            try sources.append(include_src_dir ++ "stream_encoder.c");
            try sources.append(include_src_dir ++ "stream_encoder_framing.c");
            try sources.append(include_src_dir ++ "stream_encoder_intrin_avx2.c");
            try sources.append(include_src_dir ++ "stream_encoder_intrin_sse2.c");
            try sources.append(include_src_dir ++ "stream_encoder_intrin_ssse3.c");
            try sources.append(include_src_dir ++ "window.c");

            // try sources.append(thisDir() ++ "/src/sources_linux.c");
            // if (options.x11) {
            //     try sources.append(thisDir() ++ "/src/sources_linux_x11.c");
            //     try flags.append("-D_FLAC_X11");
            // }
            // if (options.wayland) {
            //     try sources.append(thisDir() ++ "/src/sources_linux_wayland.c");
            //     try flags.append("-D_FLAC_WAYLAND");
            // }
            try flags.append(include_flac_src);
            try flags.append("-DFLAC__HAS_OGG=false");
            try flags.append("-DPACKAGE_VERSION=\"12.0.0\"");
            try flags.append(b.fmt("-DSIZE_MAX={}", .{std.math.maxInt(isize)}));
            try flags.append("-DNDEBUG");
            try flags.append("-DHAVE_LROUND");

            lib.addCSourceFiles(sources.items, flags.items);
        },
    }
}

fn linkFLACDependencies(b: *Builder, step: *std.build.LibExeObjStep, options: Options) void {
    _ = options;
    _ = b;
    step.linkLibC();
    // system_sdk.include(b, step, options.system_sdk);
    // switch (step.target_info.target.os.tag) {
    //     .windows => {
    //         step.linkSystemLibraryName("gdi32");
    //         step.linkSystemLibraryName("user32");
    //         step.linkSystemLibraryName("shell32");
    //         if (options.opengl) {
    //             step.linkSystemLibraryName("opengl32");
    //         }
    //         if (options.gles) {
    //             step.linkSystemLibraryName("GLESv3");
    //         }
    //     },
    //     .macos => {
    //         step.linkFramework("IOKit");
    //         step.linkFramework("CoreFoundation");
    //         if (options.metal) {
    //             step.linkFramework("Metal");
    //         }
    //         if (options.opengl) {
    //             step.linkFramework("OpenGL");
    //         }
    //         step.linkSystemLibraryName("objc");
    //         step.linkFramework("AppKit");
    //         step.linkFramework("CoreServices");
    //         step.linkFramework("CoreGraphics");
    //         step.linkFramework("Foundation");
    //     },
    //     else => {
    //         // Assume Linux-like
    //         if (options.wayland) {
    //             step.defineCMacro("WL_MARSHAL_FLAG_DESTROY", null);
    //         }
    //     },
    // }
}

fn ensureDependencySubmodule(allocator: std.mem.Allocator, path: []const u8) !void {
    if (std.process.getEnvVarOwned(allocator, "NO_ENSURE_SUBMODULES")) |no_ensure_submodules| {
        defer allocator.free(no_ensure_submodules);
        if (std.mem.eql(u8, no_ensure_submodules, "true")) return;
    } else |_| {}
    var child = std.ChildProcess.init(&.{ "git", "submodule", "update", "--init", path }, allocator);
    child.cwd = thisDir();
    child.stderr = std.io.getStdErr();
    child.stdout = std.io.getStdOut();

    _ = try child.spawnAndWait();
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
