const std = @import("std");
const c = @import("../c.zig");
const check = @import("error.zig").check;
const Allocator = std.mem.Allocator;

// Compile and load shader from source
fn compileAndLoadShader(alloc: std.mem.Allocator, srcPath: []const u8, spvPath: []const u8) ![]align(@alignOf(u32)) u8 {
    // Compile shader using glslc
    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &[_][]const u8{ "glslc", srcPath, "-o", spvPath },
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

    // Load compiled shader
    const file = std.fs.cwd().openFile(spvPath, .{}) catch |err| {
        std.debug.print("Failed to open compiled shader: {s}\n", .{spvPath});
        return err;
    };
    defer file.close();

    const size = try file.getEndPos();
    const data = try alloc.alignedAlloc(u8, @alignOf(u32), size);
    _ = try file.readAll(data);
    return data;
}

pub fn createShaderModule(alloc: std.mem.Allocator, srcPath: []const u8, spvPath: []const u8, gpi: c.VkDevice) !c.VkShaderModule {
    const shaderCode = try compileAndLoadShader(alloc, srcPath, spvPath);
    defer alloc.free(shaderCode);

    const createInf = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = shaderCode.len,
        .pCode = @ptrCast(@alignCast(shaderCode.ptr)),
    };
    var shdrMod: c.VkShaderModule = undefined;
    try check(c.vkCreateShaderModule(gpi, &createInf, null, &shdrMod), "Failed to create shader module");
    return shdrMod;
}
