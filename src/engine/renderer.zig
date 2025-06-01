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
const check = @import("error.zig").check;

const Allocator = std.mem.Allocator;

const MAX_FRAMES_IN_FLIGHT = 2;

const FrameData = struct {
    cmdBuffer: c.VkCommandBuffer,
    imageRdySemaphore: c.VkSemaphore,
    renderDoneSemaphore: c.VkSemaphore,
    inFlightFence: c.VkFence,
};

pub const Renderer = struct {
    alloc: Allocator,
    initilized: bool = false,
    frameNumber: u32 = 0,
    currentFrame: u32 = 0,
    stop_rendering: bool = false,

    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    dev: Device,
    swapchain: Swapchain,
    pipeline: Pipeline,
    cmdPool: c.VkCommandPool,

    frames: [MAX_FRAMES_IN_FLIGHT]FrameData,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc);
        const surface = try createSurface(window, instance);

        const dev = try Device.init(alloc, instance, surface);
        const swapchain = try Swapchain.init(alloc, dev.gpi, dev.gpu, surface, extent, dev.families);

        const pipeline = try Pipeline.init(dev.gpi, swapchain.surfaceFormat.format);
        const cmdPool = try createCmdPool(dev.gpi, dev.families.graphics);

        var frames: [MAX_FRAMES_IN_FLIGHT]FrameData = undefined;
        for (&frames) |*frame| {
            frame.cmdBuffer = try createCmdBuffer(dev.gpi, cmdPool);
            frame.imageRdySemaphore = try createSemaphore(dev.gpi);
            frame.renderDoneSemaphore = try createSemaphore(dev.gpi);
            frame.inFlightFence = try createFence(dev.gpi);
        }

        return .{
            .alloc = alloc,
            .instance = instance,
            .surface = surface,
            .dev = dev,
            .swapchain = swapchain,
            .pipeline = pipeline,
            .cmdPool = cmdPool,
            .frames = frames,
        };
    }

    pub fn draw(self: *Renderer) !void {
        const frame = &self.frames[self.currentFrame];

        // Wait for this frame's fence
        try check(c.vkWaitForFences(self.dev.gpi, 1, &frame.inFlightFence, c.VK_TRUE, std.math.maxInt(u64)), "Could not wait for inFlightFence");
        try check(c.vkResetFences(self.dev.gpi, 1, &frame.inFlightFence), "Could not reset inFlightFence");

        var imageIndex: u32 = 0;
        try check(c.vkAcquireNextImageKHR(self.dev.gpi, self.swapchain.handle, std.math.maxInt(u64), frame.imageRdySemaphore, null, &imageIndex), "could not acquire Next Image");

        try check(c.vkResetCommandBuffer(frame.cmdBuffer, 0), "Could not reset cmdBuffer");
        try recordCmdBufferSync2(self.swapchain, self.pipeline, frame.cmdBuffer, imageIndex);

        // Submit with this frame's semaphores
        const waitSemaphores = [_]c.VkSemaphore{frame.imageRdySemaphore};
        const waitStages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const signalSemaphores = [_]c.VkSemaphore{frame.renderDoneSemaphore};

        const submitInfo = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = waitSemaphores.len,
            .pWaitSemaphores = &waitSemaphores,
            .pWaitDstStageMask = &waitStages,
            .commandBufferCount = 1,
            .pCommandBuffers = &frame.cmdBuffer,
            .signalSemaphoreCount = signalSemaphores.len,
            .pSignalSemaphores = &signalSemaphores,
        };
        try check(c.vkQueueSubmit(self.dev.gQueue, 1, &submitInfo, frame.inFlightFence), "Failed to submit to Queue");

        const swapchains = [_]c.VkSwapchainKHR{self.swapchain.handle};
        const imageIndices = [_]u32{imageIndex};

        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = signalSemaphores.len,
            .pWaitSemaphores = &signalSemaphores,
            .swapchainCount = 1,
            .pSwapchains = &swapchains,
            .pImageIndices = &imageIndices,
            .pResults = null,
        };
        try check(c.vkQueuePresentKHR(self.dev.pQueue, &presentInfo), "could not present Queue");

        // Move to next frame
        self.currentFrame = (self.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    pub fn deinit(self: *Renderer) void {
        const gpi = self.dev.gpi;

        _ = c.vkDeviceWaitIdle(gpi);

        for (&self.frames) |*frame| {
            c.vkDestroySemaphore(gpi, frame.imageRdySemaphore, null);
            c.vkDestroySemaphore(gpi, frame.renderDoneSemaphore, null);
            c.vkDestroyFence(gpi, frame.inFlightFence, null);
        }

        c.vkDestroyCommandPool(gpi, self.cmdPool, null);
        self.swapchain.deinit(gpi);
        c.vkDestroyPipeline(gpi, self.pipeline.handle, null);
        c.vkDestroyPipelineLayout(gpi, self.pipeline.layout, null);
        self.dev.deinit();
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
