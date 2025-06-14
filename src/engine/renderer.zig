const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

const createInstance = @import("context/instance.zig").createInstance;
const createSurface = @import("context/surface.zig").createSurface;
const check = @import("error.zig").check;

const Device = @import("context/device.zig").Device;
const Swapchain = @import("render/swapchain.zig").Swapchain;
const FramePacer = @import("sync/framePacer.zig").FramePacer;
const Frame = @import("render/frame.zig").Frame;
const VkAllocator = @import("vma.zig").VkAllocator;

const CmdManager = @import("render/cmd.zig").CmdManager;
const recordComputeCmdBuffer = @import("render/cmd.zig").recordComputeCmdBuffer;
const recCmdBuffer = @import("render/cmd.zig").recCmdBuffer;

const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;

// For Compute Draw
//const DescriptorAllocator = @import("render/descriptor.zig").DescriptorAllocator;
const DescriptorManager = @import("render/descriptor.zig").DescriptorManager;

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    extentPtr: *c.VkExtent2D,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
    dev: Device,

    resourceMan: ResourceManager,
    descriptorManager: DescriptorManager,
    pipelineMan: PipelineManager,

    swapchain: Swapchain,
    cmdMan: CmdManager,
    pacer: FramePacer,

    shaderTimeStamp: i128,
    descriptorsUpdated: bool,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window, instance);
        const dev = try Device.init(alloc, instance, surface);

        const resourceMan = try ResourceManager.init(instance, dev.gpi, dev.gpu);
        const swapchain = try Swapchain.init(&resourceMan, alloc, &dev, surface, extent);
        const pipelineMan = try PipelineManager.init(alloc, dev.gpi, swapchain.surfaceFormat.format);

        const cmdMan = try CmdManager.init(dev.gpi, dev.families.graphics);
        const pacer = try FramePacer.init(alloc, dev.gpi, MAX_IN_FLIGHT, &cmdMan);

        // Create descriptor manager and bind image views
        const descriptorManager = try DescriptorManager.init(alloc, dev.gpi, pipelineMan.compute.descriptorSetLayout, @intCast(swapchain.imageBuckets.len));

        const shaderTimeStamp = try getFileTimeStamp("src/shader/shdr.frag");

        return .{
            .alloc = alloc,
            .extentPtr = extent,
            .instance = instance,
            .surface = surface,
            .dev = dev,
            .resourceMan = resourceMan,
            .descriptorManager = descriptorManager,
            .pipelineMan = pipelineMan,
            .swapchain = swapchain,
            .cmdMan = cmdMan,
            .pacer = pacer,
            .shaderTimeStamp = shaderTimeStamp,
            .descriptorsUpdated = false,
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
        try recCmdBuffer(&self.swapchain, &self.pipelineMan.graphics, frame.cmdBuff, frame.index);
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

    pub fn drawComputeRenderer(self: *Renderer) !void {
        //try self.checkShaderUpdate();

        // Update descriptors only once when first needed
        if (!self.descriptorsUpdated) {
            self.descriptorManager.updateAllDescriptorSets(self.dev.gpi, self.swapchain.renderImage.view);
            self.descriptorsUpdated = true;
        }

        try self.pacer.waitForGPU(self.dev.gpi);

        const frame = &self.pacer.frames[self.pacer.curFrame];

        const tracyZ2 = ztracy.ZoneNC(@src(), "AcquireImage", 0xFF0000FF);
        if (try self.swapchain.acquireImage(self.dev.gpi, frame) == false) {
            try self.renewSwapchain();
            return;
        }
        tracyZ2.End();

        const tracyZ3 = ztracy.ZoneNC(@src(), "recComputeCmd", 0x00A86BFF);
        //try recComputeCmd(&self.swapchain, &self.computePipe, frame.cmdBuff, frame.index, self.descriptorManager.sets[frame.index]);
        try recordComputeCmdBuffer(
            &self.swapchain,
            frame.cmdBuff,
            frame.index,
            self.extentPtr.*,
            &self.pipelineMan.compute, // Pass the compute pipeline
            self.descriptorManager.sets[frame.index], // Pass the correct descriptor set
        );
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
        const timeStamp = try getFileTimeStamp("src/shader/shdr.frag");
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
        self.swapchain.deinit(self.dev.gpi, &self.resourceMan);
        self.swapchain = try Swapchain.init(&self.resourceMan, self.alloc, &self.dev, self.surface, self.extentPtr);
        self.descriptorsUpdated = false; // Mark descriptors as needing update
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn renewPipeline(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);
        //self.pipe.deinit(self.dev.gpi);
        //self.pipe = try Pipeline.init(self.alloc, self.dev.gpi, self.swapchain.surfaceFormat.format);
        std.debug.print("Pipeline recreated\n", .{});
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.dev.gpi);

        self.pacer.deinit(self.alloc, self.dev.gpi);
        self.cmdMan.deinit(self.dev.gpi);
        self.swapchain.deinit(self.dev.gpi, &self.resourceMan);
        self.resourceMan.deinit();
        self.descriptorManager.deinit(self.alloc, self.dev.gpi); // Added
        self.pipelineMan.deinit(self.dev.gpi);
        self.dev.deinit();

        c.vkDestroySurfaceKHR(self.instance, self.surface, null);
        c.vkDestroyInstance(self.instance, null);
    }
};

pub fn getFileTimeStamp(src: []const u8) !i128 {
    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(src);
    const lastModified: i128 = stat.mtime;
    return lastModified;
}
