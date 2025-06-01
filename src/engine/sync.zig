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
