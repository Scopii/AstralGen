const std = @import("std");
const c = @import("../c.zig");
const Allocator = std.mem.Allocator;
const check = @import("error.zig").check;
const Frame = @import("frame.zig").Frame;

pub const FramePacer = struct {
    curFrame: u8 = 0,
    maxInFlight: u8,
    frames: []Frame,
    timeline: c.VkSemaphore,
    frameCount: u64 = 0,
    lastChecked: u64 = 0,

    // Cache for reduced allocations
    submitInf: c.VkSubmitInfo2,
    waitInf: c.VkSemaphoreSubmitInfo,
    signalInf: [2]c.VkSemaphoreSubmitInfo,
    cmdInf: c.VkCommandBufferSubmitInfo,

    pub fn init(alloc: Allocator, gpi: c.VkDevice, maxInFlight: u8, cmdPool: c.VkCommandPool) !FramePacer {
        const frames = try alloc.alloc(Frame, maxInFlight);
        for (0..maxInFlight) |i| {
            frames[i] = try Frame.init(gpi, cmdPool);
        }
        std.debug.print("Frames In Flight: {}\n", .{frames.len});

        return FramePacer{
            .frames = frames,
            .timeline = try createTimeline(gpi),
            .maxInFlight = maxInFlight,
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
                    .semaphore = null,
                    .value = 0,
                    .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
                    .deviceIndex = 0,
                },
                c.VkSemaphoreSubmitInfo{
                    .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                    .semaphore = null,
                    .value = 0,
                    .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, // Was ALL_GRAPHICS_BIT
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

    pub fn deinit(self: *FramePacer, alloc: Allocator, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.timeline, null);
        for (self.frames) |*frame| {
            frame.deinit(gpi);
        }
        alloc.free(self.frames);
    }

    // New: Efficient CPU-GPU throttling
    pub fn waitForGPU(self: *FramePacer, gpi: c.VkDevice) !void {
        if (self.frameCount < self.maxInFlight) return; // Early frames don't need waiting

        const waitVal = self.frameCount - self.maxInFlight + 1;

        // Skip check if we just waited recently (cache last check)
        if (self.lastChecked == waitVal) return;

        // Quick check - avoid syscall if already complete
        const curVal = try getTimelineVal(gpi, self.timeline);
        if (curVal >= waitVal) {
            self.lastChecked = waitVal;
            return;
        }

        // Only wait if GPU is actually behind
        try waitForTimeline(gpi, self.timeline, waitVal, 1_000_000_000);
    }

    pub fn submitFrame(self: *FramePacer, queue: c.VkQueue, frame: *Frame, renderSem: c.VkSemaphore) !void {
        self.frameCount += 1;

        self.cmdInf.commandBuffer = frame.cmdBuff;
        self.waitInf.semaphore = frame.acqSem;

        self.signalInf[0].semaphore = renderSem;
        self.signalInf[1].semaphore = self.timeline;
        self.signalInf[1].value = self.frameCount; // Timeline tracks frame completion

        self.submitInf.pWaitSemaphoreInfos = &self.waitInf;
        self.submitInf.pCommandBufferInfos = &self.cmdInf;
        self.submitInf.pSignalSemaphoreInfos = &self.signalInf;

        try check(c.vkQueueSubmit2(queue, 1, &self.submitInf, null), "Failed to submit frame");
    }

    pub fn nextFrame(self: *FramePacer) void {
        self.curFrame = (self.curFrame + 1) % self.maxInFlight;
    }

    // New: Get completion status without blocking
    pub fn getCompletedFrames(self: *FramePacer, gpi: c.VkDevice) !u64 {
        return getTimelineVal(gpi, self.timeline);
    }

    // New: Non-blocking check if specific frame is done
    pub fn isFrameComplete(self: *FramePacer, gpi: c.VkDevice, frameNum: u64) !bool {
        const completed = try self.getCompletedFrames(gpi);
        return completed >= frameNum;
    }
};

// Existing functions remain the same
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
