const std = @import("std");
const Allocator = std.mem.Allocator;
const PipelineType = @import("../vulkan/PipelineBucket.zig").PipelineType;
const config = @import("../config.zig");

pub const FileType = enum {
    asset,
    shader,
    savegame,
};

fn resolveProjectRoot(alloc: Allocator, relativePath: []const u8) ![]u8 {
    const exeDir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exeDir);
    return std.fs.path.resolve(alloc, &.{ exeDir, relativePath });
}

pub fn joinPath(alloc: Allocator, path1: []const u8, path2: []const u8) ![]u8 {
    return std.fs.path.join(alloc, &[_][]const u8{ path1, path2 });
}

pub const FileManager = struct {
    const pipelineTypes = @typeInfo(PipelineType).@"enum".fields.len;

    alloc: Allocator,
    rootPath: []u8,
    shaderPath: []const u8,
    shaderOutputPath: []const u8,
    pipelineTimeStamps: [pipelineTypes]i128,
    pipelineUpdateBools: [pipelineTypes]bool = .{false} ** pipelineTypes,

    pub fn init(alloc: Allocator) !FileManager {
        // Assign paths
        const rootPath = try resolveProjectRoot(alloc, config.rootPath);
        std.debug.print("Root Path: {s}\n", .{rootPath});
        const shaderPath = try joinPath(alloc, rootPath, config.shaderPath);
        std.debug.print("Shader Path: {s}\n", .{shaderPath});
        const shaderOutputPath = try joinPath(alloc, rootPath, config.shaderOutputPath);
        std.debug.print("Shader Output Path: {s}\n", .{shaderOutputPath});
        // Set defaults
        const currentTime = std.time.nanoTimestamp();
        const pipelineTimeStamps: [pipelineTypes]i128 = .{currentTime} ** pipelineTypes;
        // Compile on Startup if wanted
        if (config.SHADER_STARTUP_COMPILATION) {
            for (config.shaderInfos) |shaderInfo| {
                const shaderOutputName = try joinPath(alloc, shaderOutputPath, shaderInfo.outputName);
                const filePath = try joinPath(alloc, shaderPath, shaderInfo.inputName);
                try compileShader(alloc, filePath, shaderOutputName);
                alloc.free(shaderOutputName);
                alloc.free(filePath);
            }
        }

        return .{
            .alloc = alloc,
            .rootPath = rootPath,
            .shaderPath = shaderPath,
            .shaderOutputPath = shaderOutputPath,
            .pipelineTimeStamps = pipelineTimeStamps,
        };
    }

    pub fn checkShaderUpdate(self: *FileManager) !void {
        const alloc = self.alloc;
        // Check all ShaderInfos and compile if needed
        for (config.shaderInfos) |shaderInfo| {
            const filePath = try joinPath(alloc, self.shaderPath, shaderInfo.inputName);
            const newTimeStamp = try getFileTimeStamp(filePath);

            if (self.pipelineTimeStamps[@intFromEnum(shaderInfo.pipeType)] < newTimeStamp) {
                const shaderOutputPath = try joinPath(alloc, self.shaderOutputPath, shaderInfo.outputName);

                compileShader(alloc, filePath, shaderOutputPath) catch |err| {
                    std.debug.print("Tried updating Shader but compilation failed {}\n", .{err});
                };

                alloc.free(shaderOutputPath);
                self.pipelineTimeStamps[@intFromEnum(shaderInfo.pipeType)] = newTimeStamp;
                self.pipelineUpdateBools[@intFromEnum(shaderInfo.pipeType)] = true;
            }
            alloc.free(filePath);
        }
    }

    pub fn deinit(self: *FileManager) void {
        self.alloc.free(self.rootPath);
        self.alloc.free(self.shaderPath);
        self.alloc.free(self.shaderOutputPath);
    }
};

pub fn getFileTimeStamp(src: []const u8) !i128 {
    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(src);
    const ns: u64 = @intCast(stat.mtime);
    return ns; // return ns / 1_000_000 nanoseconds -> milliseconds
}

fn compileShader(alloc: Allocator, srcPath: []const u8, spvPath: []const u8) !void {
    std.debug.print("Compiling Shader: from {s} \n to -> {s}\n", .{ srcPath, spvPath });
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

pub fn readFile(self: *FileManager, fileType: FileType, relative_path: []const u8) ![]u8 {
    const base_path = self.getBasePath(fileType);
    const full_path = try std.fs.path.join(self.alloc, &.{ base_path, relative_path });
    defer self.alloc.free(full_path);

    return std.fs.cwd().readFileAlloc(self.alloc, full_path, 1_000_000_000); // 1GB limit
}
