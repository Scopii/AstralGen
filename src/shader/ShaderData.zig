const LoadedShader = @import("../shader/LoadedShader.zig").LoadedShader;
const std = @import("std");

pub const ShaderData = struct {
    rootPath: []u8 = &[_]u8{},
    shaderPath: []const u8 = &[_]u8{},
    shaderOutputPath: []const u8 = &[_]u8{},
    freshShaders: std.array_list.Managed(LoadedShader) = undefined, // Could be SlotMap
    allShaders: std.array_list.Managed(LoadedShader) = undefined, // Could be LinkedMap
};
