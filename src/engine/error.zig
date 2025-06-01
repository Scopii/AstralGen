const std = @import("std");
const c = @import("../c.zig");

pub fn check(result: c.VkResult, comptime msg: []const u8) !void {
    std.log.err("{s} ", .{ msg });
    switch (result) {
        c.VK_SUCCESS => {return;},
        c.VK_ERROR_OUT_OF_HOST_MEMORY => {std.log.err("Out of Memory\n", .{});},
        c.VK_ERROR_OUT_OF_DEVICE_MEMORY => {std.log.err("Out of GPU Memory\n", .{});},
        c.VK_ERROR_INITIALIZATION_FAILED => {std.log.err("Initialization failed\n", .{});},
        c.VK_ERROR_DEVICE_LOST => {std.log.err("GPU lost\n", .{});},
        c.VK_ERROR_MEMORY_MAP_FAILED => {std.log.err("Memory Map Failed\n", .{});},
        else => {std.log.err("Reason: {d}\n", .{result});}
    }
    return error.VulkanError;
}
