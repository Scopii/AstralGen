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
            for (config.shadersToCompile) |shader| {
                const filePath = try joinPath(alloc, shaderPath, shader.glslFile);
                const outputName = try joinPath(alloc, shaderOutputPath, shader.spvFile);
                try compileShader(alloc, filePath, outputName);
                alloc.free(filePath);
                alloc.free(outputName);
            }
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

fn compileShader(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    std.debug.print("Compiling Shader from {s} \n                to -> {s}\n", .{ srcPath, spvPath });
    // Compile shader using glslc
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "glslc", "--target-spv=spv1.6", srcPath, "-o", spvPath },
    }) catch |err| {
        std.debug.print("Failed to run glslc: {}\n", .{err});
        return err;
    };
    defer alloc.free(result.stdout);
    defer alloc.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        std.debug.print("glslc failed:\n{s}\n", .{result.stderr});
        return error.ShaderCompilationFailed;
    }
}
