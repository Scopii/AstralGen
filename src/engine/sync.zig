const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const Frame = @import("renderer.zig").Frame;

// Simplified FramePacer - focus on CPU-GPU sync only
pub const FramePacer = struct {
    timeline: c.VkSemaphore,
    currentFrame: u8 = 0,
    frameCounter: u64 = 0,
    maxFramesInFlight: u8,

    // Cache for reduced allocations
    cached_submit_info: c.VkSubmitInfo2,
    cached_wait_info: c.VkSemaphoreSubmitInfo,
    cached_signal_info: c.VkSemaphoreSubmitInfo,
    cached_cmd_info: c.VkCommandBufferSubmitInfo,

    pub fn init(gpi: c.VkDevice, maxFramesInFlight: u8) !FramePacer {
        return FramePacer{
            .timeline = try createTimelineSemaphore(gpi),
            .maxFramesInFlight = maxFramesInFlight,
            // Pre-initialize cached structures to reduce runtime overhead
            .cached_wait_info = c.VkSemaphoreSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = null,
                .value = 0,
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                .deviceIndex = 0,
            },
            .cached_signal_info = c.VkSemaphoreSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = null,
                .value = 0,
                .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                .deviceIndex = 0,
            },
            .cached_cmd_info = c.VkCommandBufferSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
                .deviceMask = 0,
            },
            .cached_submit_info = c.VkSubmitInfo2{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
                .waitSemaphoreInfoCount = 1,
                .commandBufferInfoCount = 1,
                .signalSemaphoreInfoCount = 1,
            },
        };
    }

    pub fn deinit(self: *FramePacer, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.timeline, null);
    }

    pub fn waitForGPU(self: *FramePacer, gpi: c.VkDevice) !void {
        if (self.frameCounter < self.maxFramesInFlight) return; // Early exit

        const waitValue = self.frameCounter - self.maxFramesInFlight + 1;

        // Check if already signaled before blocking wait
        const currentValue = try getTimelineSemaphoreValue(gpi, self.timeline);
        if (currentValue >= waitValue) return;

        // Only wait if necessary - reduces CPU blocking
        try waitTimelineSemaphore(gpi, self.timeline, waitValue, 1_000_000_000);
    }

    // Submit work with proper timeline tracking
    pub fn submitFrame(self: *FramePacer, queue: c.VkQueue, frame: *Frame) !void {
        self.frameCounter += 1;

        // Reuse pre-allocated structures - avoids stack allocations in hot path
        self.cached_cmd_info.commandBuffer = frame.cmdBuffer;
        self.cached_wait_info.semaphore = frame.acquiredSemaphore;
        self.cached_signal_info.semaphore = self.timeline;
        self.cached_signal_info.value = self.frameCounter;

        self.cached_submit_info.pWaitSemaphoreInfos = &self.cached_wait_info;
        self.cached_submit_info.pCommandBufferInfos = &self.cached_cmd_info;
        self.cached_submit_info.pSignalSemaphoreInfos = &self.cached_signal_info;

        try check(c.vkQueueSubmit2(queue, 1, &self.cached_submit_info, null), "Failed to submit frame");
    }

    pub fn nextFrame(self: *FramePacer) void {
        self.currentFrame = (self.currentFrame + 1) % self.maxFramesInFlight;
    }
};

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
        .semaphoreType = c.VK_SEMAPHORE_TYPE_TIMELINE,
        .initialValue = 0,
    };
    const semaphoreInfo = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
        .pNext = &semaphoreTypeCreateInfo,
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
