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
const createSemaphore = @import("sync.zig").createSemaphore;
const FramePacer = @import("sync.zig").FramePacer;
const check = @import("error.zig").check;

const Allocator = std.mem.Allocator;

const MAX_IN_FLIGHT = 1;
const DEBUG_TOGGLE = true;

pub const Frame = struct {
    cmdBuffer: c.VkCommandBuffer,
    timelineVal: u64 = 0,
    acquiredSemaphore: c.VkSemaphore,
    index: u32 = undefined,

    pub fn init(gpi: c.VkDevice, cmdPool: c.VkCommandPool) !Frame {
        var frame: Frame = undefined;
        frame.cmdBuffer = try createCmdBuffer(gpi, cmdPool);
        frame.timelineVal = 0;
        frame.acquiredSemaphore = try createSemaphore(gpi);
        return frame;
    }

    pub fn deinit(self: *Frame, gpi: c.VkDevice) void {
        c.vkDestroySemaphore(gpi, self.acquiredSemaphore, null);
    }
};

pub const Renderer = struct {
    alloc: Allocator,
    extentPtr: *c.VkExtent2D,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    device: Device,
    swapchain: Swapchain,
    pipeline: Pipeline,
    cmdPool: c.VkCommandPool,
    pacer: FramePacer,

    frames: [MAX_IN_FLIGHT]Frame,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window, instance);
        const device = try Device.init(alloc, instance, surface);
        const swapchain = try Swapchain.init(alloc, &device, surface, extent);
        const pipeline = try Pipeline.init(device.gpi, swapchain.surfaceFormat.format);
        const cmdPool = try createCmdPool(device.gpi, device.families.graphics);
        const pacer = try FramePacer.init(alloc, device.gpi, MAX_IN_FLIGHT);

        var frames: [MAX_IN_FLIGHT]Frame = undefined;
        for (0..MAX_IN_FLIGHT) |i| {
            frames[i] = try Frame.init(device.gpi, cmdPool);
        }

        return .{
            .alloc = alloc,
            .extentPtr = extent,
            .instance = instance,
            .surface = surface,
            .device = device,
            .swapchain = swapchain,
            .pipeline = pipeline,
            .cmdPool = cmdPool,
            .frames = frames,
            .pacer = pacer,
        };
    }

    pub fn draw(self: *Renderer) !void {
        const frame = &self.frames[self.pacer.currFrame];

        try self.pacer.beginFrame(frame, self.device.gpi);

        try self.swapchain.acquireImage(self.device.gpi, frame);

        // Reset and record command buffer
        try check(c.vkResetCommandBuffer(frame.cmdBuffer, 0), "Could not reset cmdBuffer");
        try recordCmdBufferSync2(self.swapchain, self.pipeline, frame.cmdBuffer, frame.index);

        try self.pacer.queueSubmit(frame, self.device.gQueue);
        try self.swapchain.present(self.device.pQueue, frame);

        self.pacer.endFrame();
    }

    pub fn recreateSwapchain(self: *Renderer, newExtent: *const c.VkExtent2D) !void {
        _ = c.vkDeviceWaitIdle(self.device.gpi);
        self.swapchain.deinit(self.device.gpi);
        self.swapchain = try Swapchain.init(self.alloc, &self.device, self.surface, newExtent);
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.device.gpi);

        for (&self.frames) |*frame| {
            frame.deinit(self.device.gpi);
        }
        self.pacer.deinit(self.device.gpi);
        c.vkDestroyCommandPool(self.device.gpi, self.cmdPool, null);
        self.swapchain.deinit(self.device.gpi);
        self.pipeline.deinit(self.device.gpi);
        self.device.deinit();
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
