const std = @import("std");
const c = @import("c");
const Context = @import("Context.zig").Context;
const check = @import("error.zig").check;
const MAX_IN_FLIGHT = @import("../config.zig").MAX_IN_FLIGHT;

pub const Scheduler = struct {
    gpi: c.VkDevice,
    frameInFlight: u8 = 0,
    maxInFlight: u8,
    cpuSyncTimeline: c.VkSemaphore,
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
        c.vkDestroySemaphore(self.gpi, self.cpuSyncTimeline, null);
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

    pub fn waitForFrame(self: *Scheduler, gpi: c.VkDevice, frameIndex: u64) !void {
        try waitForTimeline(gpi, self.cpuSyncTimeline, frameIndex, std.math.maxInt(u64));
    }

    pub fn nextFrame(self: *Scheduler) void {
        self.frameInFlight = (self.frameInFlight + 1) % self.maxInFlight;
        self.totalFrames += 1;
    }
};

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
