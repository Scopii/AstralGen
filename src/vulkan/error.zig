const std = @import("std");
const vk = @import("vk").vk;

pub fn check(result: vk.VkResult, comptime msg: []const u8) !void {
    if (result == vk.VK_SUCCESS) return;
    try errorHandle(result, msg);
}

fn errorHandle(result: vk.VkResult, comptime msg: []const u8) !void {
    switch (result) {
        vk.VK_TIMEOUT => std.log.err("{s} - Timeout", .{msg}),
        vk.VK_ERROR_OUT_OF_HOST_MEMORY => std.log.err("{s} - Out of Memory", .{msg}),
        vk.VK_ERROR_OUT_OF_DEVICE_MEMORY => std.log.err("{s} - Out of GPU Memory", .{msg}),
        vk.VK_ERROR_INITIALIZATION_FAILED => std.log.err("{s} - Initialization failed", .{msg}),
        vk.VK_ERROR_DEVICE_LOST => std.log.err("{s} - GPU lost", .{msg}),
        vk.VK_ERROR_MEMORY_MAP_FAILED => std.log.err("{s} - Memory Map Failed", .{msg}),
        else => std.log.err("{s} - Reason: {}", .{ msg, result }),
    }
    return error.VulkanError;
}
