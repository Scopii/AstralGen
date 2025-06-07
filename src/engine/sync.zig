const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const Frame = @import("frame.zig").Frame;

// Simplified FramePacer - focus on CPU-GPU sync only
pub const FramePacer = struct {
    timeline: c.VkSemaphore,
    curFrame: u8 = 0,
    frameCount: u64 = 0,
    maxInFlight: u8,

    // Cache for reduced allocations
    submitInf: c.VkSubmitInfo2,
    waitInf: c.VkSemaphoreSubmitInfo,
    signalInf: [2]c.VkSemaphoreSubmitInfo,
    cmdInf: c.VkCommandBufferSubmitInfo,

    pub fn init(gpi: c.VkDevice, maxInFlight: u8) !FramePacer {
        return FramePacer{
            .timeline = try createTimeline(gpi),
            .maxInFlight = maxInFlight,
            // Pre-initialize cached structures to reduce runtime overhead
            .waitInf = c.VkSemaphoreSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = null,
                .value = 0,
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                .deviceIndex = 0,
            },
            .signalInf = .{
                c.VkSemaphoreSubmitInfo{
                    .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                    .semaphore = null, // Will be the renderFinishedSemaphore
                    .value = 0, // Not a timeline semaphore
                    .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                    .deviceIndex = 0,
                },
                c.VkSemaphoreSubmitInfo{
                    .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                    .semaphore = null, // Will be the timeline semaphore
                    .value = 0,
                    .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                    .deviceIndex = 0,
                },
            },
            .cmdInf = c.VkCommandBufferSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
                .deviceMask = 0,
            },
            .submitInf = c.VkSubmitInfo2{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
                .waitSemaphoreInfoCount = 1,
                .commandBufferInfoCount = 1,
                .signalSemaphoreInfoCount = 2,
            },
        };
    }

    pub fn deinit(self: *FramePacer, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.timeline, null);
    }

    pub fn waitForGPU(self: *FramePacer, gpi: c.VkDevice) !void {
        if (self.frameCount < self.maxInFlight) return; // Early exit

        const waitVal = self.frameCount - self.maxInFlight + 1;
        const curVal = try getTimelineVal(gpi, self.timeline);
        if (curVal >= waitVal) return;

        try waitForTimeline(gpi, self.timeline, waitVal, 1_000_000_000);
    }

    pub fn submitFrame(self: *FramePacer, queue: c.VkQueue, frame: *Frame) !void {
        self.frameCount += 1;

        self.cmdInf.commandBuffer = frame.cmdBuff;
        self.waitInf.semaphore = frame.acqSem;

        self.signalInf[0].semaphore = frame.rendSem;
        self.signalInf[1].semaphore = self.timeline;
        self.signalInf[1].value = self.frameCount;

        self.submitInf.pWaitSemaphoreInfos = &self.waitInf;
        self.submitInf.pCommandBufferInfos = &self.cmdInf;
        self.submitInf.pSignalSemaphoreInfos = &self.signalInf;

        try check(c.vkQueueSubmit2(queue, 1, &self.submitInf, null), "Failed to submit frame");
    }

    pub fn nextFrame(self: *FramePacer) void {
        self.curFrame = (self.curFrame + 1) % self.maxInFlight;
    }
};

pub fn createSemaphore(gpi: c.VkDevice) !c.VkSemaphore {
    const seamphoreInf = c.VkSemaphoreCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    var semaphore: c.VkSemaphore = undefined;
    try check(c.vkCreateSemaphore(gpi, &seamphoreInf, null, &semaphore), "Could not create Semaphore");
    return semaphore;
}

pub fn createFence(gpi: c.VkDevice) !c.VkFence {
    const fenceInf = c.VkFenceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT, // PRE-Signaled
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
    try check(c.vkCreateSemaphore(gpi, &semaphoreInf, null, &semaphore), "Could not create  Timeline Semaphore");
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
