const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "AstralGen",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Vulkan setup
    const vulkan_zig_dep = b.dependency("vulkan_zig", .{
        .registry = b.path("vk.xml"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("vulkan", vulkan_zig_dep.module("vulkan-zig"));

    // GLFW setup - add include path and link libraries
    exe.addIncludePath(b.path("include"));
    exe.addLibraryPath(b.path("libs/GLFW"));
    exe.linkSystemLibrary("glfw3");

    // Link Vulkan library
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("vulkan-1");
    } else {
        exe.linkSystemLibrary("vulkan");
    }

    exe.linkLibC();

    // GameDev Libs (keeping your existing setup)
    const zgui_dep = b.dependency("zgui", .{
        .target = target,
        .optimize = optimize,
        .with_implot = true,
    });
    exe.root_module.addImport("zgui", zgui_dep.module("root"));
    exe.linkLibrary(zgui_dep.artifact("imgui"));

    const zjobs_dep = b.dependency("zjobs", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zjobs", zjobs_dep.module("root"));

    const zmath_dep = b.dependency("zmath", .{
        .target = target,
    });
    exe.root_module.addImport("zmath", zmath_dep.module("root"));

    const zpool_dep = b.dependency("zpool", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zpool", zpool_dep.module("root"));

    b.installArtifact(exe);

    // Copy GLFW DLL to output directory on Windows
    if (target.result.os.tag == .windows) {
        b.installFile("libs/GLFW/glfw3.dll", "bin/glfw3.dll");
    }

    // Shader compilation and copying
    const frag_shader = b.addSystemCommand(&[_][]const u8{
        "glslc",
        "src/gfx/shdr/FragShdr.frag",
        "-o",
        "zig-out/bin/FragShdr.frag.spv", // Copy to output directory
    });

    const vert_shader = b.addSystemCommand(&[_][]const u8{
        "glslc",
        "src/gfx/shdr/VertShdr.vert",
        "-o",
        "zig-out/bin/VertShdr.vert.spv", // Copy to output directory
    });

    const vert_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.2",
        "-o",
    });
    const vert_spv = vert_cmd.addOutputFileArg("vert.spv");
    vert_cmd.addFileArg(b.path("shaders/triangle.vert"));
    exe.root_module.addAnonymousImport("vertex_shader", .{
        .root_source_file = vert_spv,
    });

    const frag_cmd = b.addSystemCommand(&.{
        "glslc",
        "--target-env=vulkan1.2",
        "-o",
    });
    const frag_spv = frag_cmd.addOutputFileArg("frag.spv");
    frag_cmd.addFileArg(b.path("shaders/triangle.frag"));
    exe.root_module.addAnonymousImport("fragment_shader", .{
        .root_source_file = frag_spv,
    });

    b.getInstallStep().dependOn(&frag_shader.step);
    b.getInstallStep().dependOn(&vert_shader.step);

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
