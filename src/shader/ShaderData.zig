const sc = @import("../.configs/shaderConfig.zig");
const vkE = @import("../render/help/Enums.zig");
const Allocator = std.mem.Allocator;
const std = @import("std");

const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;

pub const ShaderData = struct {
    rootPath: []u8 = &[_]u8{},
    shaderPath: []const u8 = &[_]u8{},
    shaderOutputPath: []const u8 = &[_]u8{},
    freshShaders: std.array_list.Managed(LoadedShader) = undefined,
    allShaders: std.array_list.Managed(LoadedShader) = undefined,
};