const std = @import("std");
const c = @import("../c.zig");

pub fn check(result: c.VkResult, comptime msg: []const u8) !void {
    if (result != c.VK_SUCCESS) {
        std.log.err("{s}. Reason: {d}\n", .{ msg, result });
        return error.check;
    }
}
