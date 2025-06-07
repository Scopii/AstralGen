const std = @import("std");
const c = @import("../c.zig");

const createInstance = @import("core.zig").createInstance;
const createSurface = @import("core.zig").createSurface;
const check = @import("error.zig").check;

const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;
const Pipeline = @import("pipeline.zig").Pipeline;
const FramePacer = @import("sync.zig").FramePacer;
const Frame = @import("frame.zig").Frame;

const createCmdPool = @import("cmd.zig").createCmdPool;
const recCmdBuffer = @import("cmd.zig").recCmdBuffer;
const waitForTimeline = @import("sync.zig").waitForTimeline;

const Allocator = std.mem.Allocator;

const MAX_IN_FLIGHT = 3;
const DEBUG_TOGGLE = true;

pub const Renderer = struct {
    alloc: Allocator,
    extentPtr: *c.VkExtent2D,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    dev: Device,
    swapchain: Swapchain,
    pipe: Pipeline,
    cmdPool: c.VkCommandPool,
    pacer: FramePacer,

    frames: [MAX_IN_FLIGHT]Frame,
    timelineValues: [MAX_IN_FLIGHT]u64 = .{0} ** MAX_IN_FLIGHT,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window, instance);
        const dev = try Device.init(alloc, instance, surface);
        const swapchain = try Swapchain.init(alloc, &dev, surface, extent);
        const pipe = try Pipeline.init(dev.gpi, swapchain.surfaceFormat.format);
        const cmdPool = try createCmdPool(dev.gpi, dev.families.graphics);
        const pacer = try FramePacer.init(dev.gpi, MAX_IN_FLIGHT);

        var frames: [MAX_IN_FLIGHT]Frame = undefined;
        for (0..MAX_IN_FLIGHT) |i| {
            frames[i] = try Frame.init(dev.gpi, cmdPool);
        }

        return .{
            .alloc = alloc,
            .extentPtr = extent,
            .instance = instance,
            .surface = surface,
            .dev = dev,
            .swapchain = swapchain,
            .pipe = pipe,
            .cmdPool = cmdPool,
            .frames = frames,
            .pacer = pacer,
        };
    }

    pub fn draw(self: *Renderer) !void {
        const lastVal = self.timelineValues[self.pacer.curFrame];
        if (lastVal > 0) try waitForTimeline(self.dev.gpi, self.pacer.timeline, lastVal, 1_000_000_000);

        const frame = &self.frames[self.pacer.curFrame];

        const recreate = try self.swapchain.acquireImage(self.dev.gpi, frame);
        if (recreate == false) {
            try self.recreateSwapchain();
            return;
        }

        try check(c.vkResetCommandBuffer(frame.cmdBuff, 0), "Could not reset cmdBuffer");
        try recCmdBuffer(self.swapchain, self.pipe, frame.cmdBuff, frame.index);

        try self.pacer.submitFrame(self.dev.graphicsQ, frame);

        self.timelineValues[self.pacer.curFrame] = self.pacer.frameCount;

        try self.swapchain.present(self.dev.presentQ, frame);

        self.pacer.nextFrame();
    }

    pub fn recreateSwapchain(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);
        self.pipe.deinit(self.dev.gpi);
        self.swapchain.deinit(self.dev.gpi);
        self.swapchain = try Swapchain.init(self.alloc, &self.dev, self.surface, self.extentPtr);
        self.pipe = try Pipeline.init(self.dev.gpi, self.swapchain.surfaceFormat.format);
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);

        for (&self.frames) |*frame| {
            frame.deinit(self.dev.gpi);
        }
        self.pacer.deinit(self.dev.gpi);
        c.vkDestroyCommandPool(self.dev.gpi, self.cmdPool, null);
        self.swapchain.deinit(self.dev.gpi);
        self.pipe.deinit(self.dev.gpi);
        self.dev.deinit();
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};
