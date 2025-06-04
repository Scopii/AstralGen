const std = @import("std");
const c = @import("../c.zig");

const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;
const Pipeline = @import("pipeline.zig").Pipeline;
const createInstance = @import("instance.zig").createInstance;
const createSurface = @import("surface.zig").createSurface;
const createCmdPool = @import("command.zig").createCmdPool;
const createCmdBuffer = @import("command.zig").createCmdBuffer;
const recordCmdBufferSync2 = @import("command.zig").recordCmdBufferSync2;
const createFence = @import("sync.zig").createFence;
const createSemaphore = @import("sync.zig").createSemaphore;
const createTimelineSemaphore = @import("sync.zig").createTimelineSemaphore;
const waitTimelineSemaphore = @import("sync.zig").waitTimelineSemaphore;
const getTimelineSemaphoreValue = @import("sync.zig").getTimelineSemaphoreValue;
const check = @import("error.zig").check;

const Allocator = std.mem.Allocator;

const MAX_IN_FLIGHT = 2;
const DEBUG_TOGGLE = false;

const FrameData = struct {
    cmdBuffer: c.VkCommandBuffer,
    timelineValue: u64 = 0,
    acquisitionSemaphore: c.VkSemaphore,
};

pub const Renderer = struct {
    alloc: Allocator,
    currentFrame: u32 = 0,
    frameCounter: u64 = 1, // Global frame counter for timeline values
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    device: Device,
    swapchain: Swapchain,
    pipeline: Pipeline,
    cmdPool: c.VkCommandPool,

    // Timeline semaphore for frame completion
    timelineSemaphore: c.VkSemaphore,
    frames: [MAX_IN_FLIGHT]FrameData,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *const c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window, instance);
        const device = try Device.init(alloc, instance, surface);
        const swapchain = try Swapchain.init(alloc, &device, surface, extent);
        const pipeline = try Pipeline.init(device.gpi, &swapchain);
        const cmdPool = try createCmdPool(device.gpi, device.families.graphics);

        // Create timeline semaphore for frame sync
        const timelineSemaphore = try createTimelineSemaphore(device.gpi);

        var frames: [MAX_IN_FLIGHT]FrameData = undefined;
        for (&frames) |*frame| {
            frame.cmdBuffer = try createCmdBuffer(device.gpi, cmdPool);
            frame.timelineValue = 0;
            frame.acquisitionSemaphore = try createSemaphore(device.gpi); // Per-frame acquisition
        }

        return .{
            .alloc = alloc,
            .instance = instance,
            .surface = surface,
            .device = device,
            .swapchain = swapchain,
            .pipeline = pipeline,
            .cmdPool = cmdPool,
            .timelineSemaphore = timelineSemaphore,
            .frames = frames,
        };
    }

    pub fn draw(self: *Renderer) !void {
        const frame = &self.frames[self.currentFrame];

        // 1. Non-blocking check instead of waiting - more performant
        if (frame.timelineValue > 0) {
            const currentValue = try getTimelineSemaphoreValue(self.device.gpi, self.timelineSemaphore);
            if (currentValue < frame.timelineValue) {
                // Frame still in flight, could return early or wait with timeout
                try waitTimelineSemaphore(self.device.gpi, self.timelineSemaphore, frame.timelineValue, 1_000_000_000); // 1 second timeout
            }
        }

        // Acquire next image with this frame's acquisition semaphore
        var imageIndex: u32 = 0;
        const acquireResult = c.vkAcquireNextImageKHR(self.device.gpi, self.swapchain.handle, 1_000_000_000, frame.acquisitionSemaphore, null, &imageIndex);
        // Handle suboptimal/out-of-date swapchain
        if (acquireResult == c.VK_ERROR_OUT_OF_DATE_KHR or acquireResult == c.VK_SUBOPTIMAL_KHR) {
            // Should trigger swapchain recreation
            return error.SwapchainOutOfDate;
        }
        try check(acquireResult, "could not acquire next image");

        // Reset and record command buffer
        try check(c.vkResetCommandBuffer(frame.cmdBuffer, 0), "Could not reset cmdBuffer");
        try recordCmdBufferSync2(self.swapchain, self.pipeline, frame.cmdBuffer, imageIndex);

        // Update frame's timeline value
        frame.timelineValue = self.frameCounter;

        // Submit using vkQueueSubmit2 with both semaphores
        const cmdBufferSubmitInfo = c.VkCommandBufferSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = frame.cmdBuffer,
            .deviceMask = 0,
        };

        // Wait for this frame's acquisition
        const acquisitionWaitInfo = c.VkSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = frame.acquisitionSemaphore,
            .value = 0, // Binary semaphore, value ignored
            .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .deviceIndex = 0,
        };

        // Signal frame completion
        const timelineSignalInfo = c.VkSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = self.timelineSemaphore,
            .value = self.frameCounter,
            .stageMask = c.VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT,
            .deviceIndex = 0,
        };

        const submitInfo2 = c.VkSubmitInfo2{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = 1,
            .pWaitSemaphoreInfos = &acquisitionWaitInfo,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdBufferSubmitInfo,
            .signalSemaphoreInfoCount = 1,
            .pSignalSemaphoreInfos = &timelineSignalInfo,
        };

        try check(c.vkQueueSubmit2(self.device.gQueue, 1, &submitInfo2, null), "Failed to submit to queue");

        // Present (simplified - timeline handles synchronization)
        const swapchains = [_]c.VkSwapchainKHR{self.swapchain.handle};
        const imageIndices = [_]u32{imageIndex};

        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .swapchainCount = 1,
            .pSwapchains = &swapchains,
            .pImageIndices = &imageIndices,
        };
        try check(c.vkQueuePresentKHR(self.device.pQueue, &presentInfo), "could not present queue");

        // Advance counters
        self.frameCounter += 1;
        self.currentFrame = (self.currentFrame + 1) % MAX_IN_FLIGHT;
    }

    pub fn deinit(self: *Renderer) void {
        const gpi = self.device.gpi;
        _ = c.vkDeviceWaitIdle(gpi);

        for (&self.frames) |*frame| {
            c.vkDestroySemaphore(gpi, frame.acquisitionSemaphore, null); // Clean up per-frame semaphores
        }

        c.vkDestroySemaphore(gpi, self.timelineSemaphore, null);
        c.vkDestroyCommandPool(gpi, self.cmdPool, null);
        self.swapchain.deinit(gpi);
        c.vkDestroyPipeline(gpi, self.pipeline.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.pipeline.layout, null);
        self.device.deinit();
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
