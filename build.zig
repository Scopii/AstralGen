const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_module = b.addModule("c", .{
        .root_source_file = b.path("src/modules/c.zig"),
    });
    c_module.addIncludePath(b.path("include"));

    const exe = b.addExecutable(.{
        .name = "AstralGen",
        .root_module = b.createModule(.{ // this line was added
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.root_module.addImport("c", c_module);
    exe.linkLibCpp();
    exe.linkLibC();

    exe.addCSourceFile(.{
        .file = b.path("src/modules/vmaLink.cpp"),
        .flags = &.{"-std=c++17"}, //"-O3", "-g0"
    });
    exe.addIncludePath(b.path("include"));

    //Vulkan setup
    // const vulkan_zig_dep = b.dependency("vulkan_zig", .{
    //     .registry = b.path("vk.xml"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.root_module.addImport("vulkan-zig", vulkan_zig_dep.module("vulkan-zig"));

    // Windows Exe Metadata
    exe.addObjectFile(b.path("AstralGen.res"));

    exe.addLibraryPath(b.path("libs/SDL3"));
    exe.linkSystemLibrary("SDL3");

    exe.addLibraryPath(b.path("libs/vulkan"));
    // Link Vulkan library
    if (target.result.os.tag == .windows) {
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

    const no_bin = b.option(bool, "no-bin", "Skip binary creation for type checking") orelse false;

    if (target.result.os.tag == .windows) {
        b.installFile("libs/SDL3/SDL3.dll", "bin/SDL3.dll");
    }

    if (no_bin == false) {
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
    }

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
