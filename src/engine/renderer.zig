const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

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

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

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

    shaderTimeStamp: i128,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window, instance);
        const dev = try Device.init(alloc, instance, surface);
        const swapchain = try Swapchain.init(alloc, &dev, surface, extent);
        const pipe = try Pipeline.init(alloc, dev.gpi, swapchain.surfaceFormat.format);
        const cmdPool = try createCmdPool(dev.gpi, dev.families.graphics);
        const pacer = try FramePacer.init(alloc, dev.gpi, MAX_IN_FLIGHT, cmdPool);

        const shaderTimeStamp = try getFileTimeStamp("shaders/shdr.frag");

        return .{
            .alloc = alloc,
            .extentPtr = extent,
            .instance = instance,
            .surface = surface,
            .dev = dev,
            .swapchain = swapchain,
            .pipe = pipe,
            .cmdPool = cmdPool,
            .pacer = pacer,
            .shaderTimeStamp = shaderTimeStamp,
        };
    }

    pub fn draw(self: *Renderer) !void {
        try self.checkShaderUpdate();
        try self.pacer.waitForGPU(self.dev.gpi);

        const frame = &self.pacer.frames[self.pacer.curFrame];

        const tracyZ2 = ztracy.ZoneNC(@src(), "AcquireImage", 0xFF0000FF);
        if (try self.swapchain.acquireImage(self.dev.gpi, frame) == false) {
            try self.renewSwapchain();
            return;
        }
        tracyZ2.End();

        const tracyZ3 = ztracy.ZoneNC(@src(), "recCmdBuffer", 0x00A86BFF);
        try recCmdBuffer(&self.swapchain, &self.pipe, frame.cmdBuff, frame.index);
        tracyZ3.End();

        const tracyZ4 = ztracy.ZoneNC(@src(), "submitFrame", 0x800080FF);
        try self.pacer.submitFrame(self.dev.graphicsQ, frame, self.swapchain.imageBuckets[frame.index].rendSem);
        tracyZ4.End();

        const tracyZ5 = ztracy.ZoneNC(@src(), "Present", 0xFFC0CBFF);
        if (try self.swapchain.present(self.dev.presentQ, frame)) {
            try self.renewSwapchain();
            return;
        }
        tracyZ5.End();

        self.pacer.nextFrame();
    }

    pub fn checkShaderUpdate(self: *Renderer) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        const timeStamp = try getFileTimeStamp("shaders/shdr.frag");
        if (timeStamp != self.shaderTimeStamp) {
            self.shaderTimeStamp = timeStamp;
            try self.renewPipeline();
            std.debug.print("Shader Updated ^^\n", .{});
            return;
        }
        tracyZ1.End();
    }

    pub fn renewSwapchain(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);
        self.swapchain.deinit(self.dev.gpi);
        self.swapchain = try Swapchain.init(self.alloc, &self.dev, self.surface, self.extentPtr);
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn renewPipeline(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);
        self.pipe.deinit(self.dev.gpi);
        self.pipe = try Pipeline.init(self.alloc, self.dev.gpi, self.swapchain.surfaceFormat.format);
        std.debug.print("Pipeline recreated\n", .{});
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);

        self.pacer.deinit(self.alloc, self.dev.gpi);
        c.vkDestroyCommandPool(self.dev.gpi, self.cmdPool, null);
        self.swapchain.deinit(self.dev.gpi);
        self.pipe.deinit(self.dev.gpi);
        self.dev.deinit();
        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

pub fn getFileTimeStamp(src: []const u8) !i128 {
    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(src);
    const modification_time: i128 = stat.mtime;
    return modification_time;
}
