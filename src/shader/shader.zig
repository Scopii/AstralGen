const std = @import("std");
const c = @import("../c.zig");
const check = @import("../vulkan/error.zig").check;
const config = @import("../config.zig");
const Allocator = std.mem.Allocator;

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

pub fn createShaderModule(alloc: std.mem.Allocator, srcPath: []const u8, spvPath: []const u8, gpi: c.VkDevice) !c.VkShaderModule {
    const exe_dir = try std.fs.selfExeDirPathAlloc(alloc);
    defer alloc.free(exe_dir);

    // For runtime: look for shader folder next to exe (in parent of bin/)
    const runtimeSpvPath = try std.fs.path.join(alloc, &[_][]const u8{ exe_dir, "..", spvPath });
    defer alloc.free(runtimeSpvPath);

    if (config.SHADER_HOTLOAD) {
        // For development: resolve source path from project root
        const projectRoot = try std.fs.path.resolve(alloc, &[_][]const u8{ exe_dir, config.rootPath });
        defer alloc.free(projectRoot);

        const absSrcPath = try std.fs.path.join(alloc, &[_][]const u8{ projectRoot, srcPath });
        defer alloc.free(absSrcPath);

        // Create output directory if needed
        if (std.fs.path.dirname(runtimeSpvPath)) |dir_path| {
            std.fs.cwd().makePath(dir_path) catch {}; // Ignore if exists
        }
    }

    // Load compiled shader (works for both hotload and pre-compiled)
    const loadedShader = try loadShader(alloc, runtimeSpvPath);
    defer alloc.free(loadedShader);

    const createInf = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = loadedShader.len,
        .pCode = @ptrCast(@alignCast(loadedShader.ptr)),
    };
    var shdrMod: c.VkShaderModule = undefined;
    try check(c.vkCreateShaderModule(gpi, &createInf, null, &shdrMod), "Failed to create shader module");
    return shdrMod;
}
