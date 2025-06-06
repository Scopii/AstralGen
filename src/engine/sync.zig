const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const Frame = @import("renderer.zig").Frame;

pub const FramePacer = struct {
    alloc: Allocator,
    cmdInfos: []c.VkCommandBufferSubmitInfo,
    waitInfos: []c.VkSemaphoreSubmitInfo,
    signalInfos: []c.VkSemaphoreSubmitInfo,
    submitInfos: []c.VkSubmitInfo2,
    timeline: c.VkSemaphore,

    maxInFlight: u8 = undefined,
    currFrame: u32 = 0,
    totalFrames: u64 = 1,

    pub fn init(alloc: Allocator, gpi: c.VkDevice, maxInFlight: u8) !FramePacer {
        var cmdInfos = try alloc.alloc(c.VkCommandBufferSubmitInfo, maxInFlight);
        var waitInfos = try alloc.alloc(c.VkSemaphoreSubmitInfo, maxInFlight);
        var signalInfos = try alloc.alloc(c.VkSemaphoreSubmitInfo, maxInFlight);
        var submitInfos = try alloc.alloc(c.VkSubmitInfo2, maxInFlight);

        for (0..maxInFlight) |i| {
            cmdInfos[i] = c.VkCommandBufferSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
                .commandBuffer = null, //PLACEHOLDER frame.cmdBuffer
                .deviceMask = 0,
            };

            waitInfos[i] = c.VkSemaphoreSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = null, //PLACEHOLDER frame.acquiredSemaphore
                .value = 0,
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                .deviceIndex = 0,
            };

            signalInfos[i] = c.VkSemaphoreSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = null, //PLACEHOLDER self.timeline
                .value = 0, //PLACEHOLDER totalFrames
                .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                .deviceIndex = 0,
            };

            submitInfos[i] = c.VkSubmitInfo2{
                .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
                .waitSemaphoreInfoCount = 1,
                .pWaitSemaphoreInfos = &waitInfos[i],
                .commandBufferInfoCount = 1,
                .pCommandBufferInfos = &cmdInfos[i],
                .signalSemaphoreInfoCount = 1, // Only timeline semaphore
                .pSignalSemaphoreInfos = &signalInfos[i],
            };
        }

        const timeline = try createTimelineSemaphore(gpi);

        return .{
            .alloc = alloc,
            .cmdInfos = cmdInfos,
            .waitInfos = waitInfos,
            .signalInfos = signalInfos,
            .submitInfos = submitInfos,
            .timeline = timeline,
            .maxInFlight = maxInFlight,
        };
    }

    pub fn deinit(self: *FramePacer, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.timeline, null);
        self.alloc.free(self.cmdInfos);
        self.alloc.free(self.waitInfos);
        self.alloc.free(self.signalInfos);
        self.alloc.free(self.submitInfos);
    }

    pub fn waitForFrame(self: *FramePacer, gpi: c.VkDevice, frameVal: u64, timeout: u64) !void {
        if (frameVal == 0) return;

        const currVal = try getTimelineSemaphoreValue(gpi, self.timeline);
        if (currVal < frameVal) {
            try waitTimelineSemaphore(gpi, self.timeline, frameVal, timeout);
        }
    }

    pub fn beginFrame(self: *FramePacer, frame: *Frame, gpi: c.VkDevice) !void {
        try self.waitForFrame(gpi, frame.timelineVal, 1_000_000_000);
    }

    pub fn endFrame(self: *FramePacer) void {
        self.totalFrames += 1;
        self.currFrame = (self.currFrame + 1) % self.maxInFlight;
    }

    pub fn queueSubmit(self: *FramePacer, frame: *Frame, queue: c.VkQueue) !void {
        frame.timelineVal = self.totalFrames;
        // Set command buffer
        self.cmdInfos[self.currFrame].commandBuffer = frame.cmdBuffer;
        // Set wait semaphore (acquisition)
        self.waitInfos[self.currFrame].semaphore = frame.acquiredSemaphore;
        // Set signal semaphore (timeline only)
        self.signalInfos[self.currFrame].semaphore = self.timeline;
        self.signalInfos[self.currFrame].value = self.totalFrames;

        try check(c.vkQueueSubmit2(queue, 1, &self.submitInfos[self.currFrame], null), "Failed to submit to queue");
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
