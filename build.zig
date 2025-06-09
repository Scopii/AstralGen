const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "AstralGen",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // GLFW setup - add include path and link libraries
    exe.addIncludePath(b.path("include"));

    exe.addLibraryPath(b.path("libs/SDL3"));
    exe.linkSystemLibrary("SDL3");

    exe.addLibraryPath(b.path("libs/vulkan"));
    // Link Vulkan library
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("vulkan-1");
    } else {
        exe.linkSystemLibrary("vulkan");
    }

    exe.linkLibC();

    // GameDev Libs:

    // Tracy
    const options = .{
        .enable_ztracy = b.option(
            bool,
            "enable_ztracy",
            "Enable Tracy profile markers",
        ) orelse false,
        .enable_fibers = b.option(
            bool,
            "enable_fibers",
            "Enable Tracy fiber support",
        ) orelse false,
        .on_demand = b.option(
            bool,
            "on_demand",
            "Build tracy with TRACY_ON_DEMAND",
        ) orelse false,
    };
    const ztracy = b.dependency("ztracy", .{
        .enable_ztracy = options.enable_ztracy,
        .enable_fibers = options.enable_fibers,
        .on_demand = options.on_demand,
    });
    exe.root_module.addImport("ztracy", ztracy.module("root"));
    exe.linkLibrary(ztracy.artifact("tracy"));

    const zgui_dep = b.dependency("zgui", .{ .target = target, .optimize = optimize, .with_implot = true, .backend = .glfw_vulkan });

    // Get Vulkan SDK path and add headers
    const vulkan_sdk = std.process.getEnvVarOwned(b.allocator, "VULKAN_SDK") catch null;
    if (vulkan_sdk) |sdk_path| {
        const vulkan_include = std.fs.path.join(b.allocator, &.{ sdk_path, "Include" }) catch unreachable;
        zgui_dep.artifact("imgui").addIncludePath(.{ .cwd_relative = vulkan_include });
    }

    exe.root_module.addImport("zgui", zgui_dep.module("root"));
    exe.linkLibrary(zgui_dep.artifact("imgui"));

    const zjobs_dep = b.dependency("zjobs", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zjobs", zjobs_dep.module("root"));

    const zmath_dep = b.dependency("zmath", .{ .target = target });
    exe.root_module.addImport("zmath", zmath_dep.module("root"));

    const zpool_dep = b.dependency("zpool", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zpool", zpool_dep.module("root"));

    b.installArtifact(exe);

    // Copy GLFW DLL to output directory on Windows
    if (target.result.os.tag == .windows) {
        b.installFile("libs/SDL3/SDL3.dll", "bin/SDL3.dll");
    }

    const vert_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.3",
        "-o",
        // "zig-out/bin/VertShdr.vert.spv"
    });
    const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
    vert_cmd.addFileArg(b.path("shaders/shdr.vert"));
    exe.root_module.addAnonymousImport("vert_shdr", .{ .root_source_file = vert_spv });

    const frag_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.3",
        "-o",
        // "zig-out/bin/VertShdr.vert.spv"
    });
    const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
    frag_cmd.addFileArg(b.path("shaders/shdr.frag"));
    exe.root_module.addAnonymousImport("frag_shdr", .{ .root_source_file = frag_spv });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe.root_module,
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
