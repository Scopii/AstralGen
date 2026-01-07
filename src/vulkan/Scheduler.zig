const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const vh = @import("Helpers.zig");

pub const Scheduler = struct {
    gpi: vk.VkDevice,
    frameInFlight: u8 = 0,
    maxInFlight: u8,
    cpuSyncTimeline: vk.VkSemaphore,
    totalFrames: u64 = 0,
    lastChecked: u64 = 0,

    pub fn init(context: *const Context, maxInFlight: u8) !Scheduler {
        std.debug.print("Scheduler: In Flight {}\n", .{maxInFlight});

        return Scheduler{
            .gpi = context.gpi,
            .cpuSyncTimeline = try createTimeline(context.gpi),
            .maxInFlight = maxInFlight,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        vk.vkDestroySemaphore(self.gpi, self.cpuSyncTimeline, null);
    }

    pub fn waitForGPU(self: *Scheduler) !void {
        const gpi = self.gpi;
        if (self.totalFrames < self.maxInFlight) return;
        const waitVal = self.totalFrames - self.maxInFlight + 1;

        if (self.lastChecked == waitVal) return;

        const curVal = try getTimelineVal(gpi, self.cpuSyncTimeline);
        if (curVal >= waitVal) {
            self.lastChecked = waitVal;
            return;
        }
        try waitForTimeline(gpi, self.cpuSyncTimeline, waitVal, 1_000_000_000); // Only wait if GPU is behind
    }

    pub fn waitForFrame(self: *Scheduler, gpi: vk.VkDevice, frameIndex: u64) !void {
        try waitForTimeline(gpi, self.cpuSyncTimeline, frameIndex, std.math.maxInt(u64));
    }

    pub fn nextFrame(self: *Scheduler) void {
        self.frameInFlight = (self.frameInFlight + 1) % self.maxInFlight;
        self.totalFrames += 1;
    }
};

pub fn createSemaphore(gpi: vk.VkDevice) !vk.VkSemaphore {
    const semaphoreInf = vk.VkSemaphoreCreateInfo{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    var semaphore: vk.VkSemaphore = undefined;
    try vh.check(vk.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Semaphore");
    return semaphore;
}

pub fn createFence(gpi: vk.VkDevice) !vk.VkFence {
    const fenceInf = vk.VkFenceCreateInfo{
        .sType = vk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var fence: vk.VkFence = undefined;
    try vh.check(vk.vkCreateFence(gpi, &fenceInf, null, &fence), "Could not create Fence");
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
    try vh.check(vk.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create Timeline Semaphore");
    return semaphore;
}

pub fn waitForTimeline(gpi: vk.VkDevice, semaphore: vk.VkSemaphore, val: u64, timeout: u64) !void {
    const waitInf = vk.VkSemaphoreWaitInfo{
        .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,
        .semaphoreCount = 1,
        .pSemaphores = &semaphore,
        .pValues = &val,
    };
    try vh.check(vk.vkWaitSemaphores(gpi, &waitInf, timeout), "Failed to wait for timeline semaphore");
}

pub fn getTimelineVal(gpi: vk.VkDevice, semaphore: vk.VkSemaphore) !u64 {
    var val: u64 = 0;
    try vh.check(vk.vkGetSemaphoreCounterValue(gpi, semaphore, &val), "Failed to get timeline semaphore value");
    return val;
}
