const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const Frame = @import("renderer.zig").Frame;

// Simplified FramePacer - focus on CPU-GPU sync only
pub const FramePacer = struct {
    timeline: c.VkSemaphore,
    currentFrame: u32 = 0,
    frameCounter: u64 = 0,
    maxFramesInFlight: u32,

    pub fn init(gpi: c.VkDevice, maxFramesInFlight: u32) !FramePacer {
        return FramePacer{
            .timeline = try createTimelineSemaphore(gpi),
            .maxFramesInFlight = maxFramesInFlight,
        };
    }

    pub fn deinit(self: *FramePacer, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.timeline, null);
    }

    // Wait for GPU to finish frame that would conflict
    pub fn waitForGPU(self: *FramePacer, gpi: c.VkDevice) !void {
        if (self.frameCounter >= self.maxFramesInFlight) {
            const waitValue = self.frameCounter - self.maxFramesInFlight + 1;
            try waitTimelineSemaphore(gpi, self.timeline, waitValue, 1_000_000_000);
        }
    }

    // Submit work with proper timeline tracking
    pub fn submitFrame(self: *FramePacer, queue: c.VkQueue, frame: *Frame) !void {
        self.frameCounter += 1;

        // Build submit info on-demand (cleaner than pre-allocated arrays)
        const cmdInfo = c.VkCommandBufferSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = frame.cmdBuffer,
            .deviceMask = 0,
        };

        const waitInfo = c.VkSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = frame.acquiredSemaphore,
            .value = 0, // Binary semaphore
            .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .deviceIndex = 0,
        };

        const signalInfo = c.VkSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = self.timeline,
            .value = self.frameCounter, // Timeline tracks completion
            .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .deviceIndex = 0,
        };

        const submitInfo = c.VkSubmitInfo2{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = 1,
            .pWaitSemaphoreInfos = &waitInfo,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdInfo,
            .signalSemaphoreInfoCount = 1,
            .pSignalSemaphoreInfos = &signalInfo,
        };

        try check(c.vkQueueSubmit2(queue, 1, &submitInfo, null), "Failed to submit frame");
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
