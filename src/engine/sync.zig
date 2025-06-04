const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;

pub fn createSemaphore(device: c.VkDevice) !c.VkSemaphore {
    const semaphoreInfo = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var semaphore: c.VkSemaphore = undefined;
    try check(c.vkCreateSemaphore(device, &semaphoreInfo, null, &semaphore), "Could not create Semaphore");
    return semaphore;
}

pub fn createFence(device: c.VkDevice) !c.VkFence {
    const fenceInfo = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence: c.VkFence = undefined;
    try check(c.vkCreateFence(device, &fenceInfo, null, &fence), "Could not create Fence");
    return fence;
}

pub fn createTimelineSemaphore(device: c.VkDevice) !c.VkSemaphore {
    var semaphoreTypeCreateInfo: c.VkSemaphoreTypeCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
        .pNext = null,
        .semaphoreType = c.VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = 0,
    };
    const semaphoreInfo = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = &semaphoreTypeCreateInfo,
        .flags = 0,
    };
    var semaphore: c.VkSemaphore = undefined;
    try check(c.vkCreateSemaphore(device, &semaphoreInfo, null, &semaphore), "Could not create  Timeline Semaphore");
    return semaphore;
}

pub fn waitTimelineSemaphore(device: c.VkDevice, semaphore: c.VkSemaphore, value: u64, timeout: u64) !void {
    const waitInfo = c.VkSemaphoreWaitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &semaphore,
        .pValues = &value,
    };
    try check(c.vkWaitSemaphores(device, &waitInfo, timeout), "Failed to wait for timeline semaphore");
}

pub fn getTimelineSemaphoreValue(device: c.VkDevice, semaphore: c.VkSemaphore) !u64 {
    var value: u64 = 0;
    try check(c.vkGetSemaphoreCounterValue(device, semaphore, &value), "Failed to get timeline semaphore value");
    return value;
}
