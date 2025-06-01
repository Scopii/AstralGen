const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;

pub fn createSemaphore(device: c.VkDevice) !c.VkSemaphore {
    const semaphoreInfo = c.VkSemaphoreCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    var semaphore: c.VkSemaphore = undefined;

    if (c.vkCreateSemaphore(device, &semaphoreInfo, null, &semaphore) != c.VK_SUCCESS) {
        return error.couldNotCreateSemaphore;
    }
    return semaphore;
}

pub fn createFence(device: c.VkDevice) !c.VkFence {
    const fenceInfo = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence: c.VkFence = undefined;

    if (c.vkCreateFence(device, &fenceInfo, null, &fence) != c.VK_SUCCESS) {
        return error.couldNotCreateFence;
    }
    return fence;
}
