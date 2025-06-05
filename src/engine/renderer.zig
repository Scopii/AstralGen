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
const SyncManager = @import("sync.zig").SyncManager;
const createTimelineSemaphore = @import("sync.zig").createTimelineSemaphore;
const waitTimelineSemaphore = @import("sync.zig").waitTimelineSemaphore;
const getTimelineSemaphoreValue = @import("sync.zig").getTimelineSemaphoreValue;
const check = @import("error.zig").check;

const Allocator = std.mem.Allocator;

const MAX_IN_FLIGHT = 1;
const DEBUG_TOGGLE = false;

pub const FrameData = struct {
    cmdBuffer: c.VkCommandBuffer,
    timelineVal: u64 = 0,
    acquiredSemaphore: c.VkSemaphore,
};

pub const Renderer = struct {
    alloc: Allocator,
    currFrame: u32 = 0,
    totalFrames: u64 = 1,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    device: Device,
    swapchain: Swapchain,
    pipeline: Pipeline,
    cmdPool: c.VkCommandPool,
    syncMan: SyncManager,
    imageIndices: [MAX_IN_FLIGHT]u32 = undefined,

    // Timeline semaphore for frame completion
    frames: [MAX_IN_FLIGHT]FrameData,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *const c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window, instance);
        const device = try Device.init(alloc, instance, surface);
        const swapchain = try Swapchain.init(alloc, &device, surface, extent);
        const pipeline = try Pipeline.init(device.gpi, &swapchain);
        const cmdPool = try createCmdPool(device.gpi, device.families.graphics);
        const syncMan = try SyncManager.init(alloc, device.gpi, MAX_IN_FLIGHT);

        var frames: [MAX_IN_FLIGHT]FrameData = undefined;
        for (&frames) |*frame| {
            frame.cmdBuffer = try createCmdBuffer(device.gpi, cmdPool);
            frame.timelineVal = 0;
            frame.acquiredSemaphore = try createSemaphore(device.gpi);
        }

        return .{
            .alloc = alloc,
            .instance = instance,
            .surface = surface,
            .device = device,
            .swapchain = swapchain,
            .pipeline = pipeline,
            .cmdPool = cmdPool,
            .frames = frames,
            .syncMan = syncMan,
        };
    }

    pub fn draw(self: *Renderer) !void {
        const frame = &self.frames[self.currFrame];

        try self.syncMan.waitForFrame(self.device.gpi, frame.timelineVal, 1_000_000_000);

        // Acquire next image
        const acquireResult = c.vkAcquireNextImageKHR(
            self.device.gpi,
            self.swapchain.handle,
            1_000_000_000,
            frame.acquiredSemaphore,
            null,
            &self.imageIndices[self.currFrame],
        );

        if (acquireResult == c.VK_ERROR_OUT_OF_DATE_KHR or acquireResult == c.VK_SUBOPTIMAL_KHR) {
            // Should trigger swapchain recreation
            return error.SwapchainOutOfDate;
        }
        try check(acquireResult, "could not acquire next image");

        // Reset and record command buffer
        try check(c.vkResetCommandBuffer(frame.cmdBuffer, 0), "Could not reset cmdBuffer");
        try recordCmdBufferSync2(self.swapchain, self.pipeline, frame.cmdBuffer, self.imageIndices[self.currFrame]);

        // Update frame's timeline value
        frame.timelineVal = self.totalFrames;

        try self.syncMan.queueSubmit(frame, self.device.gQueue, self.currFrame, self.totalFrames);

        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain.handle,
            .pImageIndices = &self.imageIndices[self.currFrame],
        };
        try check(c.vkQueuePresentKHR(self.device.pQueue, &presentInfo), "could not present queue");

        // Advance counters
        self.totalFrames += 1;
        self.currFrame = (self.currFrame + 1) % MAX_IN_FLIGHT;
    }

    pub fn recreateSwapchain(self: *Renderer, newExtent: *const c.VkExtent2D) !void {
        _ = c.vkDeviceWaitIdle(self.device.gpi);

        self.swapchain.deinit(self.device.gpi);
        self.swapchain = try Swapchain.init(self.alloc, &self.device, self.surface, newExtent);

        // Recreate pipeline if needed
        c.vkDestroyPipeline(self.device.gpi, self.pipeline.handle, null);
        c.vkDestroyPipelineLayout(self.device.gpi, self.pipeline.layout, null);
        self.pipeline = try Pipeline.init(self.device.gpi, &self.swapchain);
    }

    pub fn deinit(self: *Renderer) void {
        const gpi = self.device.gpi;
        _ = c.vkDeviceWaitIdle(gpi);

        for (&self.frames) |*frame| {
            c.vkDestroySemaphore(gpi, frame.acquiredSemaphore, null);
        }

        self.syncMan.deinit(gpi);
        c.vkDestroyCommandPool(gpi, self.cmdPool, null);
        self.swapchain.deinit(gpi);
        c.vkDestroyPipeline(gpi, self.pipeline.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.pipeline.layout, null);
        self.device.deinit();
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
