const std = @import("std");
const c = @import("c");

pub fn check(result: c.VkResult, comptime msg: []const u8) !void {
    if (result == c.VK_SUCCESS) return;
    try errorHandle(result, msg);
}

fn errorHandle(result: c.VkResult, comptime msg: []const u8) !void {
    switch (result) {
        c.VK_TIMEOUT => std.log.err("{s} - Timeout", .{msg}),
        c.VK_ERROR_OUT_OF_HOST_MEMORY => std.log.err("{s} - Out of Memory", .{msg}),
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => std.log.err("{s} - Out of GPU Memory", .{msg}),
        c.VK_ERROR_INITIALIZATION_FAILED => std.log.err("{s} - Initialization failed", .{msg}),
        c.VK_ERROR_DEVICE_LOST => std.log.err("{s} - GPU lost", .{msg}),
        c.VK_ERROR_MEMORY_MAP_FAILED => std.log.err("{s} - Memory Map Failed", .{msg}),
        else => std.log.err("{s} - Reason: {}", .{ msg, result }),
    }
    return error.VulkanError;
}
