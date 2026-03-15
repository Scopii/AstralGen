const sc = @import("../.configs/shaderConfig.zig");
const vkE = @import("../render/help/Enums.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

const LoadedShader = @import("LoadedShader.zig").LoadedShader;
const ShaderInf = @import("ShaderInf.zig").ShaderInf;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;

const ShaderData = @import("ShaderData.zig").ShaderData;
const ShaderQueue = @import("ShaderQueue.zig").ShaderQueue;
const RendererQueue = @import("../render/RendererQueue.zig").RendererQueue;

pub const ShaderId = packed struct { val: u8 };

pub const ShaderSys = struct {
    pub fn init(shaderData: *ShaderData, alloc: Allocator) !void {
        // Assign paths
        const root = try resolveProjectRoot(alloc, sc.ROOT_PATH);
        std.debug.print("Root Path {s}\n", .{root});
        const shaderPath = try joinPath(alloc, root, sc.SHADER_PATH);
        std.debug.print("Shader Path {s}\n", .{shaderPath});
        const shaderOutputPath = try joinPath(alloc, root, sc.SPRV_PATH);
        std.debug.print("Shader Output Path {s}\n", .{shaderOutputPath});

        shaderData.rootPath = root;
        shaderData.shaderPath = shaderPath;
        shaderData.shaderOutputPath = shaderOutputPath;
        shaderData.freshShaders = std.array_list.Managed(LoadedShader).init(alloc);
        shaderData.allShaders = std.array_list.Managed(LoadedShader).init(alloc);
    }

    pub fn deinit(shaderData: *const ShaderData, alloc: Allocator) void {
        alloc.free(shaderData.rootPath);
        alloc.free(shaderData.shaderPath);
        alloc.free(shaderData.shaderOutputPath);
        shaderData.freshShaders.deinit();
        shaderData.allShaders.deinit();
    }

    pub fn update(shaderData: *ShaderData, _: *ShaderQueue, rendererQueue: *RendererQueue, memoryMan: *MemoryManager) !void {
        // for (shaderQueue.get()) |shaderEvent| {
        //     switch (shaderEvent) {
        //         .compileShader => {
        //             const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "compileShader");
        //             const Payload = std.meta.Child(PayloadPtr);

        //             const loadedShaderPtr = try memoryMan.getGlobalArena().create(Payload);
        //             loadedShaderPtr.* = .{ .bufId = rc.objectSB.id, .data = slice };
        //             self.rendererQueue.append(.{ .updateBuffer = loadedShaderPtr });
        //         },
        //     }
        // }

        for (shaderData.freshShaders.items) |freshShader| {
            // const PayloadPtr = @FieldType(RendererQueue.RendererEvent, "compileShader");
            // const Payload = std.meta.Child(PayloadPtr);
            const loadedShaderPtr = try memoryMan.getGlobalArena().create(LoadedShader);
            loadedShaderPtr.* = freshShader;
            rendererQueue.append(.{ .addShader = loadedShaderPtr });
        }
    }

    pub fn loadShaders(shaderData: *ShaderData, alloc: Allocator, shaderInfos: []const ShaderInf) !void {
        if (sc.SHADER_STARTUP_COMPILATION) {
            try compileShadersParallel(alloc, shaderData.shaderPath, shaderData.shaderOutputPath, shaderInfos);
        }
        const curTime = std.time.nanoTimestamp();

        for (shaderInfos) |shaderConfig| {
            const spvPath = try joinPath(alloc, shaderData.shaderOutputPath, shaderConfig.spvFile);
            defer alloc.free(spvPath);
            const data = try loadShader(alloc, spvPath);
            const newShader = LoadedShader{ .shaderInf = shaderConfig, .timeStamp = curTime, .data = data };
            try shaderData.freshShaders.append(newShader);
            try shaderData.allShaders.append(newShader);
        }
    }

    pub fn freeFreshShaders(shaderData: *ShaderData, alloc: Allocator) void {
        for (shaderData.freshShaders.items) |*loadedShader| {
            alloc.free(loadedShader.data);
        }
        shaderData.freshShaders.clearRetainingCapacity();
    }

    pub fn checkShaderUpdates(shaderData: *ShaderData, alloc: Allocator) !void {
        for (shaderData.allShaders.items) |*loadedShader| {
            const filePath = try joinPath(alloc, shaderData.shaderPath, loadedShader.shaderInf.file);
            defer alloc.free(filePath);
            const newTimeStamp = try getFileTimeStamp(filePath);

            if (loadedShader.timeStamp < newTimeStamp) {
                const shaderOutputPath = try joinPath(alloc, shaderData.shaderOutputPath, loadedShader.shaderInf.spvFile);
                defer alloc.free(shaderOutputPath);

                compileShader(alloc, filePath, shaderOutputPath, loadedShader.shaderInf.typ, shaderData.shaderPath) catch |err| {
                    std.debug.print("Tried updating Shader but compilation failed {}\n", .{err});
                };

                const data = try loadShader(alloc, shaderOutputPath);
                loadedShader.data = data;
                loadedShader.timeStamp = newTimeStamp;

                try shaderData.freshShaders.append(loadedShader.*);
                std.debug.print("Hotloaded: {s}\n", .{loadedShader.shaderInf.file});
            }
        }
    }
};

fn loadShader(alloc: Allocator, spvPath: []const u8) !LoadedShader.alignedShader {
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

fn threadCompile(src: []const u8, dst: []const u8, stage: vkE.ShaderStage, includePath: []const u8, failedBool: *std.atomic.Value(bool)) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // Thread Save
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    //transpileSlang(alloc, src, dst, "hlsl")
    const result = compileShader(alloc, src, dst, stage, includePath);
    if (result == error.ShaderCompilationFailed) failedBool.store(true, .seq_cst);

    std.heap.page_allocator.free(src);
    std.heap.page_allocator.free(dst);
}

pub fn compileShadersParallel(alloc: std.mem.Allocator, absShaderPath: []const u8, absShaderOutputPath: []const u8, shaders: []const ShaderInf) !void {
    var threads = std.array_list.Managed(std.Thread).init(alloc);
    defer threads.deinit();

    var failed = std.atomic.Value(bool).init(false);

    for (shaders) |shader| {
        const src = try joinPath(std.heap.page_allocator, absShaderPath, shader.file);
        const dst = try joinPath(std.heap.page_allocator, absShaderOutputPath, shader.spvFile);
        const t = try std.Thread.spawn(.{}, threadCompile, .{ src, dst, shader.typ, absShaderPath, &failed });
        try threads.append(t);
    }
    for (threads.items) |thread| thread.join();

    if (failed.load(.seq_cst)) return error.ShaderCompilationFailed;
}

fn compileShader(alloc: Allocator, srcPath: []const u8, spvPath: []const u8, stage: vkE.ShaderStage, includePath: []const u8) !void {
    var shaderFormat: u8 = 0;
    if (std.mem.endsWith(u8, srcPath, ".hlsl")) shaderFormat = 1;
    if (std.mem.endsWith(u8, srcPath, ".glsl")) shaderFormat = 2;
    if (std.mem.endsWith(u8, srcPath, ".slang")) shaderFormat = 3;

    const timeBefore = std.time.milliTimestamp();

    switch (shaderFormat) {
        1 => try compileHLSL(alloc, srcPath, spvPath, stage),
        2 => try compileGLSL(alloc, srcPath, spvPath, stage),
        3 => try compileSLANG(alloc, srcPath, spvPath, stage, includePath),
        else => {
            std.debug.print("Could not find Shader Format for {s}!\n", .{srcPath});
            return error.ShaderCompilationFailed;
        },
    }
    std.debug.print("[{d}ms] Compiled {s} -> {s}\n", .{ std.time.milliTimestamp() - timeBefore, srcPath, spvPath });
}

fn compileGLSL(alloc: Allocator, srcPath: []const u8, spvPath: []const u8, stage: vkE.ShaderStage) !void {
    var stageString: []const u8 = "compute";
    if (stage == .vert) stageString = "vertex";
    if (stage == .frag) stageString = "fragment";
    if (stage == .meshWithTask or stage == .meshNoTask) stageString = "mesh";
    if (stage == .task) stageString = "task";

    const stageFlag = try std.fmt.allocPrint(alloc, "-fshader-stage={s}", .{stageString});
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

fn compileSLANG(alloc: Allocator, srcPath: []const u8, spvPath: []const u8, stage: vkE.ShaderStage, includePath: []const u8) !void {
    var stageString: []const u8 = "compute";
    if (stage == .vert) stageString = "vertex";
    if (stage == .frag) stageString = "fragment";
    if (stage == .meshWithTask or stage == .meshNoTask) stageString = "mesh";
    if (stage == .task) stageString = "task";

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{
            "slangc",
            srcPath,
            "-target",
            "spirv",
            "-profile",
            "sm_6_6",
            "-fvk-use-scalar-layout",
            "-matrix-layout-column-major",
            "-stage",
            stageString,
            "-entry",
            "main",
            "-I",
            includePath,
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

fn compileHLSL(alloc: Allocator, srcPath: []const u8, spvPath: []const u8, stage: vkE.ShaderStage) !void {
    var profile: []const u8 = "cs_6_6"; // default compute
    if (stage == .vert) profile = "vs_6_6";
    if (stage == .frag) profile = "ps_6_6";
    if (stage == .meshWithTask or stage == .meshNoTask) profile = "ms_6_6";
    if (stage == .task) profile = "as_6_6";

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
