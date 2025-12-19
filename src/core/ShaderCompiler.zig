const std = @import("std");
const Allocator = std.mem.Allocator;
const shaderCon = @import("../configs/shaderConfig.zig");
const ShaderStage = @import("../vulkan/ShaderObject.zig").ShaderStage;
const ShaderInfo = shaderCon.ShaderInfo;

const alignedShader = []align(@alignOf(u32)) u8;

pub const LoadedShader = struct {
    data: alignedShader,
    timeStamp: i128,
    shaderConfig: ShaderInfo,
};

pub const ShaderCompiler = struct {
    alloc: Allocator,
    rootPath: []u8,
    shaderPath: []const u8,
    shaderOutputPath: []const u8,
    freshShaders: std.array_list.Managed(LoadedShader),
    allShaders: std.array_list.Managed(LoadedShader),

    pub fn init(alloc: Allocator) !ShaderCompiler {
        // Assign paths
        const root = try resolveProjectRoot(alloc, shaderCon.rootPath);
        std.debug.print("Root Path {s}\n", .{root});
        const shaderPath = try joinPath(alloc, root, shaderCon.glslPath);
        std.debug.print("Shader Path {s}\n", .{shaderPath});
        const shaderOutputPath = try joinPath(alloc, root, shaderCon.sprvPath);
        std.debug.print("Shader Output Path {s}\n", .{shaderOutputPath});

        return .{
            .alloc = alloc,
            .rootPath = root,
            .shaderPath = shaderPath,
            .shaderOutputPath = shaderOutputPath,
            .freshShaders = std.array_list.Managed(LoadedShader).init(alloc),
            .allShaders = std.array_list.Managed(LoadedShader).init(alloc),
        };
    }

    pub fn deinit(self: *ShaderCompiler) void {
        self.alloc.free(self.rootPath);
        self.alloc.free(self.shaderPath);
        self.alloc.free(self.shaderOutputPath);
        self.freshShaders.deinit();
        self.allShaders.deinit();
    }

    pub fn pullFreshShaders(self: *ShaderCompiler) []LoadedShader {
        return self.freshShaders.items;
    }

    pub fn loadShaders(self: *ShaderCompiler, shaderConfigs: []const ShaderInfo) !void {
        const alloc = self.alloc;
        try compileShadersParallel(alloc, self.shaderPath, self.shaderOutputPath, shaderConfigs);
        const curTime = std.time.nanoTimestamp();

        for (shaderConfigs) |shaderConfig| {
            const spvPath = try joinPath(alloc, self.shaderOutputPath, shaderConfig.spvFile);
            defer alloc.free(spvPath);
            const data = try loadShader(alloc, spvPath);
            const newShader = LoadedShader{ .shaderConfig = shaderConfig, .timeStamp = curTime, .data = data };
            try self.freshShaders.append(newShader);
            try self.allShaders.append(newShader);
        }
    }

    pub fn freeFreshShaders(self: *ShaderCompiler) void {
        for (self.freshShaders.items) |*loadedShader| {
            self.alloc.free(loadedShader.data);
        }
        self.freshShaders.clearRetainingCapacity();
    }

    pub fn checkShaderUpdates(self: *ShaderCompiler) !void {
        const alloc = self.alloc;

        for (self.allShaders.items) |*loadedShader| {
            const filePath = try joinPath(alloc, self.shaderPath, loadedShader.shaderConfig.glslFile);
            defer alloc.free(filePath);
            const newTimeStamp = try getFileTimeStamp(filePath);

            if (loadedShader.timeStamp < newTimeStamp) {
                const shaderOutputPath = try joinPath(alloc, self.shaderOutputPath, loadedShader.shaderConfig.spvFile);
                defer alloc.free(shaderOutputPath);

                compileShader(alloc, filePath, shaderOutputPath) catch |err| {
                    std.debug.print("Tried updating Shader but compilation failed {}\n", .{err});
                };

                const data = try loadShader(alloc, shaderOutputPath);
                loadedShader.data = data;
                loadedShader.timeStamp = newTimeStamp;

                try self.freshShaders.append(loadedShader.*);
                std.debug.print("Hotloaded: {s}\n", .{loadedShader.shaderConfig.glslFile});
            }
        }
    }
};

fn loadShader(alloc: Allocator, spvPath: []const u8) !alignedShader {
    const file = try std.fs.cwd().openFile(spvPath, .{});
    defer file.close();

    const size = try file.getEndPos();
    const wordCount = std.math.divCeil(usize, size, 4) catch unreachable;
    const words = try alloc.alloc(u32, wordCount);
    errdefer alloc.free(words);

    const bytes = std.mem.sliceAsBytes(words);
    _ = try file.readAll(bytes[0..size]);

    return bytes[0..size];
}

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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // Thread Save
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    //transpileSlang(alloc, src, dst, "hlsl")
    compileShader(alloc, src, dst) catch |err| {
        std.debug.print("Thread Compile Failed: {}\n", .{err});
    };
    std.heap.page_allocator.free(src);
    std.heap.page_allocator.free(dst);
}

pub fn compileShadersParallel(alloc: std.mem.Allocator, absShaderPath: []const u8, absShaderOutputPath: []const u8, shaders: []const ShaderInfo) !void {
    var threads = std.array_list.Managed(std.Thread).init(alloc);
    defer threads.deinit();

    for (shaders) |shader| {
        const src = try joinPath(std.heap.page_allocator, absShaderPath, shader.glslFile);
        const dst = try joinPath(std.heap.page_allocator, absShaderOutputPath, shader.spvFile);
        const t = try std.Thread.spawn(.{}, threadCompile, .{ src, dst });
        try threads.append(t);
    }
    for (threads.items) |thread| thread.join();
}

fn compileShader(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var shaderFormat: u8 = 0;
    if (std.mem.endsWith(u8, srcPath, ".hlsl")) shaderFormat = 1;
    if (std.mem.endsWith(u8, srcPath, ".glsl")) shaderFormat = 2;
    if (std.mem.endsWith(u8, srcPath, ".slang")) shaderFormat = 3;

    const timeBefore = std.time.milliTimestamp();

    switch (shaderFormat) {
        1 => try compileHLSL(alloc, srcPath, spvPath),
        2 => try compileGLSL(alloc, srcPath, spvPath),
        3 => try compileSLANG(alloc, srcPath, spvPath),
        else => {
            std.debug.print("Could not find Shader Format for {s}!\n", .{srcPath});
            return error.ShaderCompilationFailed;
        },
    }
    std.debug.print("[{d}ms] Compiled {s} -> {s}\n", .{ std.time.milliTimestamp() - timeBefore, srcPath, spvPath });
}

fn compileGLSL(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var stage: []const u8 = "compute";
    if (std.mem.endsWith(u8, srcPath, "vert.glsl")) stage = "vertex";
    if (std.mem.endsWith(u8, srcPath, "frag.glsl")) stage = "fragment";
    if (std.mem.endsWith(u8, srcPath, "mesh.glsl")) stage = "mesh";
    if (std.mem.endsWith(u8, srcPath, "task.glsl")) stage = "task";

    const stageFlag = try std.fmt.allocPrint(alloc, "-fshader-stage={s}", .{stage});
    defer alloc.free(stageFlag);

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "glslc", "--target-env=vulkan1.3", stageFlag, srcPath, "-o", spvPath },
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

fn compileSLANG(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
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

// fn transpileSlang(alloc: Allocator, srcPath: []const u8, dstPath: []const u8, format: []const u8) !void {
//     // Format is "hlsl" or "glsl"
//     const result = std.process.Child.run(.{
//         .allocator = alloc,
//         .argv = &[_][]const u8{ "slangc", srcPath, "-target", format, "-entry", "main", "-o", dstPath },
//     }) catch |err| {
//         std.debug.print("Failed to run SlangC: {}\n", .{err});
//         return err;
//     };
//     defer alloc.free(result.stdout);
//     defer alloc.free(result.stderr);

//     if (result.term != .Exited or result.term.Exited != 0) {
//         std.debug.print("Shader Compilation Failed:\n{s}\n", .{result.stderr});
//         return error.ShaderTranspileFailed;
//     }
// }

fn compileHLSL(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    var profile: []const u8 = "cs_6_6"; // default compute
    if (std.mem.endsWith(u8, srcPath, "vert.hlsl")) profile = "vs_6_6";
    if (std.mem.endsWith(u8, srcPath, "frag.hlsl")) profile = "ps_6_6";
    if (std.mem.endsWith(u8, srcPath, "mesh.hlsl")) profile = "ms_6_6";
    if (std.mem.endsWith(u8, srcPath, "task.hlsl")) profile = "as_6_6";

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
