const FixedList = @import("../.structures/FixedList.zig").FixedList;
const std = @import("std");
const LoadedShader = @import("LoadedShader.zig").LoadedShader;

pub const ShaderQueue = struct {
    shaderEvents: FixedList(ShaderEvent, 127) = .{},

    pub fn append(self: *ShaderQueue, rendererEvent: ShaderEvent) void {
        self.shaderEvents.append(rendererEvent) catch |err| std.debug.print("RendererQueue.appendEvent failed: {}\n", .{err});
    }

    pub fn get(self: *ShaderQueue) []const ShaderEvent {
        return self.shaderEvents.constSlice();
    }

    pub fn clear(self: *ShaderQueue) void {
        self.shaderEvents.clear();
    }

    pub const ShaderEvent = union(enum) {
        // compileShader: *LoadedShader,
    };
};