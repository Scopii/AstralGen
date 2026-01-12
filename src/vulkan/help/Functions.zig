const vk = @import("../../modules/vk.zig").c;
const vkFn = @import("../../modules/vk.zig");
const vhE = @import("Enums.zig");
const std = @import("std");

pub fn getShaderBit(stageEnum: vhE.ShaderStage) vk.VkShaderStageFlagBits {
    return switch (stageEnum) {
        .comp => vk.VK_SHADER_STAGE_COMPUTE_BIT,
        .vert => vk.VK_SHADER_STAGE_VERTEX_BIT,
        .tessControl => vk.VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT,
        .tessEval => vk.VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT,
        .geometry => vk.VK_SHADER_STAGE_GEOMETRY_BIT,
        .task => vk.VK_SHADER_STAGE_TASK_BIT_EXT,
        .mesh => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .meshNoTask => vk.VK_SHADER_STAGE_MESH_BIT_EXT,
        .frag => vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
}

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

pub fn Handle(comptime _: type) type {
    return packed struct {
        id: u32,
        // pub inline fn raw(self: @This()) u32 {
        //     return self.id;
        // }
    };
}

pub fn setObjectName(device: vk.VkDevice, handle: anytype, objectType: vk.VkObjectType, name: []const u8) void {
    if (vkFn.vkSetDebugUtilsObjectNameEXT == null) return;

    var nameBuffer: [64]u8 = undefined;
    const len = @min(name.len, 63);
    @memcpy(nameBuffer[0..len], name[0..len]);
    nameBuffer[len] = 0; // Null terminate

    const nameInfo = vk.VkDebugUtilsObjectNameInfoEXT{
        .sType = vk.VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
        .objectType = objectType,
        .objectHandle = @intFromPtr(handle), // Cast handle (pointer) to u64
        .pObjectName = &nameBuffer,
    };

    _ = vkFn.vkSetDebugUtilsObjectNameEXT.?(device, &nameInfo);
}
// USAGE:
// vh.setObjectName(self.gpi, buffer.handle, vk.VK_OBJECT_TYPE_BUFFER, buffer.name);

pub fn createSemaphore(gpi: vk.VkDevice) !vk.VkSemaphore {
    const semaphoreInf = vk.VkSemaphoreCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    var semaphore: vk.VkSemaphore = undefined;
    try check(vk.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Semaphore");
    return semaphore;
}

pub fn createFence(gpi: vk.VkDevice) !vk.VkFence {
    const fenceInf = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence: vk.VkFence = undefined;
    try check(vk.vkCreateFence(gpi, &fenceInf, null, &fence), "Could not create Fence");
    return fence;
}

pub fn createTimeline(gpi: vk.VkDevice) !vk.VkSemaphore {
    var semaphoreTypeInf: vk.VkSemaphoreTypeCreateInfo = .{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
        .semaphoreType = vk.VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = 0,
    };
    const semaphoreInf = vk.VkSemaphoreCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = &semaphoreTypeInf,
    };
    var semaphore: vk.VkSemaphore = undefined;
    try check(vk.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Timeline Semaphore");
    return semaphore;
}

pub fn waitForTimeline(gpi: vk.VkDevice, semaphore: vk.VkSemaphore, val: u64, timeout: u64) !void {
    const waitInf = vk.VkSemaphoreWaitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &semaphore,
        .pValues = &val,
    };
    try check(vk.vkWaitSemaphores(gpi, &waitInf, timeout), "Failed to wait for timeline semaphore");
}

pub fn getTimelineVal(gpi: vk.VkDevice, semaphore: vk.VkSemaphore) !u64 {
    var val: u64 = 0;
    try check(vk.vkGetSemaphoreCounterValue(gpi, semaphore, &val), "Failed to get timeline semaphore value");
    return val;
}
