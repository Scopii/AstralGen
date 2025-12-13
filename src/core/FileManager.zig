const std = @import("std");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");

pub const FileManager = struct {
    const stepCount = config.renderSeq.len;

    alloc: Allocator,
    rootPath: []u8,
    shaderPath: []const u8,
    shaderOutputPath: []const u8,
    layoutTimeStamps: [stepCount]i128,
    layoutUpdateBools: [stepCount]bool = .{false} ** stepCount,

    pub fn init(alloc: Allocator) !FileManager {
        // Assign paths
        const root = try resolveProjectRoot(alloc, config.rootPath);
        std.debug.print("Root Path {s}\n", .{root});
        const shaderPath = try joinPath(alloc, root, config.glslPath);
        std.debug.print("Shader Path {s}\n", .{shaderPath});
        const shaderOutputPath = try joinPath(alloc, root, config.sprvPath);
        std.debug.print("Shader Output Path {s}\n", .{shaderOutputPath});
        // Set defaults
        const curTime = std.time.nanoTimestamp();
        const layoutTimeStamps: [stepCount]i128 = .{curTime} ** stepCount;
        // Compile on Startup if wanted
        if (config.SHADER_STARTUP_COMPILATION) {
            try compileAllShadersParallel(alloc, shaderPath, shaderOutputPath);
        }

        return .{
            .alloc = alloc,
            .rootPath = root,
            .shaderPath = shaderPath,
            .shaderOutputPath = shaderOutputPath,
            .layoutTimeStamps = layoutTimeStamps,
        };
    }

    pub fn checkShaderUpdate(self: *FileManager) !void {
        const alloc = self.alloc;
        // Check all ShaderInfos and compile if needed
        for (config.renderSeq, 0..) |shaderLayout, i| {
            for (shaderLayout.shaders) |shader| {
                const filePath = try joinPath(alloc, self.shaderPath, shader.glslFile);
                const newTimeStamp = try getFileTimeStamp(filePath);

                if (self.layoutTimeStamps[i] < newTimeStamp) {
                    const shaderOutputPath = try joinPath(alloc, self.shaderOutputPath, shader.spvFile);

                    compileShader(alloc, filePath, shaderOutputPath) catch |err| {
                        std.debug.print("Tried updating Shader but compilation failed {}\n", .{err});
                    };

                    alloc.free(shaderOutputPath);
                    self.layoutTimeStamps[i] = newTimeStamp;
                    self.layoutUpdateBools[i] = true;
                }
                alloc.free(filePath);
            }
        }
    }

    pub fn deinit(self: *FileManager) void {
        self.alloc.free(self.rootPath);
        self.alloc.free(self.shaderPath);
        self.alloc.free(self.shaderOutputPath);
    }
};

pub fn resolveProjectRoot(alloc: Allocator, relativePath: []const u8) ![]u8 {
    const exeDir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exeDir);
    return std.fs.path.resolve(alloc, &.{ exeDir, relativePath });
}

pub fn joinPath(alloc: Allocator, path1: []const u8, path2: []const u8) ![]u8 {
    return std.fs.path.join(alloc, &[_][]const u8{ path1, path2 });
}

pub fn getFileTimeStamp(src: []const u8) !i128 {
    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(src);
    const ns: u64 = @intCast(stat.mtime);
    return ns; // return ns / 1_000_000 nanoseconds -> milliseconds
}

fn threadCompile(src: []const u8, dst: []const u8) void {
    // Use a thread-safe allocator for internal temporary strings (like formatted args)
    // GeneralPurposeAllocator is slow for this. C allocator is best if available.
    // Or just use page_allocator for temp storage.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    compileShader(alloc, src, dst) catch |err| {
        // Use a mutex if you want clean printing, otherwise output might mix
        std.debug.print("Thread Compile Failed: {}\n", .{err});
    };

    // Free the path strings passed to this thread
    // (We assume the caller allocated them using a global allocator for us to own)
    std.heap.page_allocator.free(src);
    std.heap.page_allocator.free(dst);
}

pub fn compileAllShadersParallel(
    alloc: std.mem.Allocator,
    absShaderPath: []const u8, // Pass the resolved source folder
    absShaderOutputPath: []const u8, // Pass the resolved output folder
) !void {
    var threads = std.ArrayList(std.Thread).init(alloc);
    defer threads.deinit();

    for (config.shadersToCompile) |shader| {
        const src = try joinPath(std.heap.page_allocator, absShaderPath, shader.glslFile);
        const dst = try joinPath(std.heap.page_allocator, absShaderOutputPath, shader.spvFile);

        const t = try std.Thread.spawn(.{}, threadCompile, .{ src, dst });
        try threads.append(t);
    }

    for (threads.items) |t| {
        t.join();
    }
}

fn compileShader(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var shaderFormat: u8 = 0;
    if (std.mem.endsWith(u8, srcPath, ".hlsl")) shaderFormat = 1;
    if (std.mem.endsWith(u8, srcPath, ".glsl")) shaderFormat = 2;
    if (std.mem.endsWith(u8, srcPath, ".slang")) shaderFormat = 3;

    const time1 = std.time.milliTimestamp();

    switch (shaderFormat) {
        1 => try compileShaderHLSL(alloc, srcPath, spvPath),
        2 => try compileShaderGLSL(alloc, srcPath, spvPath),
        3 => try compileShaderSLANG(alloc, srcPath, spvPath),
        else => {
            std.debug.print("Could not find Shader Format for {s}!\n", .{srcPath});
            return error.ShaderCompilationFailed;
        },
    }
    const duration = std.time.milliTimestamp() - time1;
    std.debug.print("[{d}ms] Compiled {s} -> {s}\n", .{ duration, srcPath, spvPath });
}

fn compileShaderGLSL(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var stage: []const u8 = "compute";
    if (std.mem.endsWith(u8, srcPath, "vert.glsl")) stage = "vertex";
    if (std.mem.endsWith(u8, srcPath, "frag.glsl")) stage = "fragment";
    if (std.mem.endsWith(u8, srcPath, "mesh.glsl")) stage = "mesh";
    if (std.mem.endsWith(u8, srcPath, "task.glsl")) stage = "task";

    const stageFlag = try std.fmt.allocPrint(alloc, "-fshader-stage={s}", .{stage});
    defer alloc.free(stageFlag);

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{
            "glslc",
            "--target-env=vulkan1.3",
            stageFlag,
            srcPath,
            "-o",
            spvPath,
        },
    }) catch |err| {
        std.debug.print("Failed to run GLSLC: {}\n", .{err});
        return err;
    };
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("Shader Compilation Failed:\n{s}\n", .{result.stderr});
        return error.ShaderCompilationFailed;
    }
}

fn compileShaderSLANG(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var stage: []const u8 = "compute"; // default
    if (std.mem.endsWith(u8, srcPath, "vert.slang")) stage = "vertex";
    if (std.mem.endsWith(u8, srcPath, "frag.slang")) stage = "fragment";
    if (std.mem.endsWith(u8, srcPath, "mesh.slang")) stage = "mesh";
    if (std.mem.endsWith(u8, srcPath, "task.slang")) stage = "task";

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{
            "slangc",
            srcPath,
            "-target",
            "spirv",
            "-profile",
            "sm_6_6",
            "-stage",
            stage,
            "-entry",
            "main",
            "-o",
            spvPath,
            "-fvk-use-entrypoint-name",
        },
    }) catch |err| {
        std.debug.print("Failed to run SlangC: {}\n", .{err});
        return err;
    };
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("Shader Compilation Failed:\n{s}\n", .{result.stderr});
        return error.ShaderCompilationFailed;
    }
}

fn compileShaderHLSL(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var profile: []const u8 = "cs_6_6"; // default compute
    if (std.mem.endsWith(u8, srcPath, "vert.hlsl")) profile = "vs_6_6";
    if (std.mem.endsWith(u8, srcPath, "frag.hlsl")) profile = "ps_6_6";
    if (std.mem.endsWith(u8, srcPath, "mesh.hlsl")) profile = "ms_6_6"; // Mesh shader 6.5
    if (std.mem.endsWith(u8, srcPath, "task.hlsl")) profile = "as_6_6"; // Amplification (Task) shader

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{
            "dxc",
            "-spirv", // Output SPIR-V
            "-T", profile, // Target Profile
            "-E",                         "main", // Entry point
            "-fspv-target-env=vulkan1.3", srcPath,
            "-Fo",                        spvPath,
        },
    }) catch |err| {
        std.debug.print("Failed to run DXC: {}\n", .{err});
        return err;
    };
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("Shader Compilation Failed:\n{s}\n", .{result.stderr});
        return error.ShaderCompilationFailed;
    }
}
