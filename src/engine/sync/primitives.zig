const c = @import("../../c.zig");
const check = @import("../error.zig").check;

pub fn createSemaphore(gpi: c.VkDevice) !c.VkSemaphore {
    const seamphoreInf = c.VkSemaphoreCreateInfo{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    var semaphore: c.VkSemaphore = undefined;
    try check(c.vkCreateSemaphore(gpi, &seamphoreInf, null, &semaphore), "Could not create Semaphore");
    return semaphore;
}

pub fn createFence(gpi: c.VkDevice) !c.VkFence {
    const fenceInf = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence: c.VkFence = undefined;
    try check(c.vkCreateFence(gpi, &fenceInf, null, &fence), "Could not create Fence");
    return fence;
}

pub fn createTimeline(gpi: c.VkDevice) !c.VkSemaphore {
    var semaphoreTypeInf: c.VkSemaphoreTypeCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,
        .semaphoreType = c.VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = 0,
    };
    const semaphoreInf = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = &semaphoreTypeInf,
    };
    var semaphore: c.VkSemaphore = undefined;
    try check(c.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Timeline Semaphore");
    return semaphore;
}

pub fn waitForTimeline(gpi: c.VkDevice, semaphore: c.VkSemaphore, val: u64, timeout: u64) !void {
    const waitInf = c.VkSemaphoreWaitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &semaphore,
        .pValues = &val,
    };
    try check(c.vkWaitSemaphores(gpi, &waitInf, timeout), "Failed to wait for timeline semaphore");
}

pub fn getTimelineVal(gpi: c.VkDevice, semaphore: c.VkSemaphore) !u64 {
    var val: u64 = 0;
    try check(c.vkGetSemaphoreCounterValue(gpi, semaphore, &val), "Failed to get timeline semaphore value");
    return val;
}
