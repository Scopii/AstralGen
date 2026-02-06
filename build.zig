const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check = b.step("check", "check everything");

    const c_module = b.addModule("c", .{ .root_source_file = b.path("src/modules/c.zig") });

    const exe = b.addExecutable(.{
        .name = "AstralGen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    check.dependOn(&exe.step);

    exe.root_module.addImport("c", c_module);

    exe.linkLibCpp();
    exe.linkLibC();

    // 2. Add dependencies
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .backend = .sdl3_vulkan,
    });
    exe.root_module.addImport("zgui", zgui_dep.module("root"));
    exe.linkLibrary(zgui_dep.artifact("imgui"));

    // 3. Setup Include Paths
    const local_include_path = b.path("include"); // Cause imgui_bridge.h

    const include_paths = [_]std.Build.LazyPath{
        local_include_path,
    };

    for (include_paths) |path| {
        exe.addIncludePath(path);
        c_module.addIncludePath(path);
    }

    exe.addCSourceFile(.{
        .file = b.path("src/modules/vmaLink.cpp"),
        .flags = &.{"-std=c++17"}, //"-O3", "-g0"
    });

    // 5. Link Libraries

    exe.addLibraryPath(b.path("libs/SDL3"));
    exe.linkSystemLibrary("SDL3");

    exe.addLibraryPath(b.path("libs/vulkan"));
    // Link Vulkan library
    if (target.result.os.tag == .windows) {
        exe.addObjectFile(b.path("AstralGen.res")); // Windows Exe Metadata
        exe.linkSystemLibrary("vulkan-1");
    } else {
        exe.linkSystemLibrary("vulkan");
    }

    // GameDev Libs:

    // Tracy
    const options = .{
        .enable_ztracy = b.option(bool, "enable_ztracy", "Enable Tracy profile markers") orelse false,
        .enable_fibers = b.option(bool, "enable_fibers", "Enable Tracy fiber support") orelse false,
        .on_demand = b.option(bool, "on_demand", "Build tracy with TRACY_ON_DEMAND") orelse false,
    };
    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = options.enable_ztracy,
        .enable_fibers = options.enable_fibers,
        .on_demand = options.on_demand,
    });
    exe.root_module.addImport("ztracy", ztracy.module("root"));
    exe.linkLibrary(ztracy.artifact("tracy"));

    const zjobs_dep = b.dependency("zjobs", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zjobs", zjobs_dep.module("root"));

    const zmath_dep = b.dependency("zmath", .{ .target = target });
    exe.root_module.addImport("zmath", zmath_dep.module("root"));

    const zpool_dep = b.dependency("zpool", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zpool", zpool_dep.module("root"));

    if (target.result.os.tag == .windows) {
        b.installFile("libs/SDL3/SDL3.dll", "bin/SDL3.dll");
    }

    b.installArtifact(exe);

    // Create Shader directory if needed
    std.fs.cwd().makePath("zig-out/shader") catch |err| {
        std.debug.print("Failed to create directory '{s}': {}\n", .{ "zig-out/shader", err });
    };

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
