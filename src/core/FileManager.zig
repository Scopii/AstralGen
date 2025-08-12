const std = @import("std");
const Allocator = std.mem.Allocator;

const config = @import("../config.zig");

pub const FileType = enum {
    asset,
    shader,
    savegame,
};

fn resolveProjectRoot(alloc: Allocator, relative_path: []const u8) ![]u8 {
    const exeDir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exeDir);
    return std.fs.path.resolve(alloc, &.{ exeDir, relative_path });
}

pub fn joinPath(alloc: Allocator, path1: []const u8, path2: []const u8) ![]u8 {
    const joinedPath = try std.fs.path.join(alloc, &[_][]const u8{ path1, path2 });
    defer alloc.free(joinedPath);
    std.debug.print("joined path: {s}\n", .{joinedPath});
    return joinedPath;
}

pub const FileManager = struct {
    alloc: Allocator,
    rootPath: []u8,
    shaderPath: []const u8,

    pub fn init(alloc: Allocator) !FileManager {
        const resolvedRoot = try resolveProjectRoot(alloc, config.rootPath);
        std.debug.print("Root Folder: {s}\n", .{resolvedRoot});
        const shaderPath = try joinPath(alloc, resolvedRoot, config.shaderPath);

        return .{
            .alloc = alloc,
            .rootPath = resolvedRoot,
            .shaderPath = shaderPath,
        };
    }

    pub fn deinit(self: *FileManager) void {
        self.alloc.free(self.rootPath);
    }
};

// pub fn getFileTimeStamp(alloc: Allocator, src: []const u8) !u64 {
//     const absolutePath = try joinPath(alloc, src);
//     defer alloc.free(absolutePath);

//     const cwd = std.fs.cwd();
//     const stat = try cwd.statFile(absolutePath);
//     const ns: u64 = @intCast(stat.mtime);
//     return ns / 1_000_000; // nanoseconds -> milliseconds
// }

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

fn loadShader(alloc: Allocator, spvPath: []const u8) ![]align(@alignOf(u32)) u8 {
    std.debug.print("Loading shader: {s}\n", .{spvPath});
    const file = std.fs.cwd().openFile(spvPath, .{}) catch |err| {
        std.debug.print("Failed to load shader: {s}\n", .{spvPath});
        return err;
    };
    defer file.close();

    const size = try file.getEndPos();
    const data = try alloc.alignedAlloc(u8, @alignOf(u32), size);
    _ = try file.readAll(data);
    return data;
}

pub fn readFile(self: *FileManager, fileType: FileType, relative_path: []const u8) ![]u8 {
    const base_path = self.getBasePath(fileType);
    const full_path = try std.fs.path.join(self.alloc, &.{ base_path, relative_path });
    defer self.alloc.free(full_path);

    return std.fs.cwd().readFileAlloc(self.alloc, full_path, 1_000_000_000); // 1GB limit
}
