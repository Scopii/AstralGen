const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

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

const MAX_IN_FLIGHT = 1;
const DEBUG_TOGGLE = false;

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
        std.debug.print("Frames In Flight: {}\n", .{frames.len});

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
        const tracyZ1 = ztracy.ZoneNC(@src(), "WaitForGPU", 0x0000FFFF);
        try self.pacer.waitForGPU(self.dev.gpi);
        tracyZ1.End();

        const frame = &self.frames[self.pacer.curFrame];

        const tracyZ2 = ztracy.ZoneNC(@src(), "AcquireImage", 0xFF0000FF);
        if (try self.swapchain.acquireImage(self.dev.gpi, frame) == false) {
            try self.recreateSwapchain();
            return;
        }
        tracyZ2.End();

        const tracyZ3 = ztracy.ZoneNC(@src(), "recCmdBuffer", 0x00A86BFF);
        //try check(c.vkResetCommandBuffer(frame.cmdBuff, 0), "Could not reset cmdBuffer");
        try recCmdBuffer(&self.swapchain, &self.pipe, frame.cmdBuff, frame.index);
        tracyZ3.End();

        const tracyZ4 = ztracy.ZoneNC(@src(), "submitFrame", 0x800080FF);
        try self.pacer.submitFrame(self.dev.graphicsQ, frame, self.swapchain.imgBucket.getRenderSemaphore(frame.index));
        tracyZ4.End();

        const tracyZ5 = ztracy.ZoneNC(@src(), "Present", 0xFFC0CBFF);
        if (try self.swapchain.present(self.dev.presentQ, frame)) {
            try self.recreateSwapchain();
            return;
        }
        tracyZ5.End();

        self.pacer.nextFrame();
    }

    pub fn recreateSwapchain(self: *Renderer) !void {
        std.debug.print("\nWindow Reacreation:\n", .{});
        _ = c.vkDeviceWaitIdle(self.dev.gpi);
        self.pipe.deinit(self.dev.gpi);
        self.swapchain.deinit(self.dev.gpi);
        self.swapchain = try Swapchain.init(self.alloc, &self.dev, self.surface, self.extentPtr);
        self.pipe = try Pipeline.init(self.dev.gpi, self.swapchain.surfaceFormat.format);
        std.debug.print("\n", .{});
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
