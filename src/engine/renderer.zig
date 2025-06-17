const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

const check = @import("error.zig").check;

const Context = @import("render/Context.zig").Context;
const Swapchain = @import("render/Swapchain.zig").Swapchain;
const FramePacer = @import("sync/FramePacer.zig").FramePacer;
const Frame = @import("sync/FramePacer.zig").Frame;
const VkAllocator = @import("vma.zig").VkAllocator;
const CmdManager = @import("render/CmdManager.zig").CmdManager;
const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;
const recordComputeCmdBuffer = @import("render/CmdManager.zig").recordComputeCmdBuffer;
const recCmdBuffer = @import("render/CmdManager.zig").recCmdBuffer;

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    extentPtr: *c.VkExtent2D,
    context: Context,
    resourceMan: ResourceManager,
    descriptorManager: DescriptorManager,
    pipelineMan: PipelineManager,
    swapchain: Swapchain,
    cmdMan: CmdManager,
    pacer: FramePacer,
    fragmentTimeStemp: i128,
    computeTimeStemp: i128,
    descriptorsUpdated: bool,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: *c.VkExtent2D) !Renderer {
        const context = try Context.init(alloc, window, DEBUG_TOGGLE);
        const resourceMan = try ResourceManager.init(&context);
        const swapchain = try Swapchain.init(&resourceMan, alloc, &context, extent);
        const pipelineMan = try PipelineManager.init(alloc, &context, swapchain.surfaceFormat.format);
        const cmdMan = try CmdManager.init(context.gpi, context.families.graphics);
        const pacer = try FramePacer.init(alloc, context.gpi, MAX_IN_FLIGHT, &cmdMan);
        const descriptorManager = try DescriptorManager.init(alloc, context.gpi, pipelineMan.compute.descriptorSetLayout, @intCast(swapchain.swapBuckets.len));
        const fragmentTimeStemp = try getFileTimeStamp("src/shader/shdr.frag");
        const computeTimeStemp = try getFileTimeStamp("src/shader/shdr.comp");

        return .{
            .alloc = alloc,
            .extentPtr = extent,
            .context = context,
            .resourceMan = resourceMan,
            .descriptorManager = descriptorManager,
            .pipelineMan = pipelineMan,
            .swapchain = swapchain,
            .cmdMan = cmdMan,
            .pacer = pacer,
            .fragmentTimeStemp = fragmentTimeStemp,
            .computeTimeStemp = computeTimeStemp,
            .descriptorsUpdated = false,
        };
    }

    pub fn draw(self: *Renderer) !void {
        try self.checkShaderUpdate();
        try self.pacer.waitForGPU(self.context.gpi);

        const frame = &self.pacer.frames[self.pacer.curFrame];

        const tracyZ2 = ztracy.ZoneNC(@src(), "AcquireImage", 0xFF0000FF);
        if (try self.swapchain.acquireImage(self.context.gpi, frame) == false) {
            try self.renewSwapchain();
            return;
        }
        tracyZ2.End();

        const tracyZ3 = ztracy.ZoneNC(@src(), "recCmdBuffer", 0x00A86BFF);
        try recCmdBuffer(&self.swapchain, &self.pipelineMan.graphics, frame.cmdBuff, frame.index);
        tracyZ3.End();

        const tracyZ4 = ztracy.ZoneNC(@src(), "submitFrame", 0x800080FF);
        try self.pacer.submitFrame(self.context.graphicsQ, frame, self.swapchain.swapBuckets[frame.index].rendSem);
        tracyZ4.End();

        const tracyZ5 = ztracy.ZoneNC(@src(), "Present", 0xFFC0CBFF);
        if (try self.swapchain.present(self.context.presentQ, frame)) {
            try self.renewSwapchain();
            return;
        }
        tracyZ5.End();

        self.pacer.nextFrame();
    }

    pub fn drawComputeRenderer(self: *Renderer) !void {
        try self.checkComputeShaderUpdate();

        // Update descriptors only once when first needed
        if (!self.descriptorsUpdated) {
            self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
            self.descriptorsUpdated = true;
        }

        try self.pacer.waitForGPU(self.context.gpi);
        const frame = &self.pacer.frames[self.pacer.curFrame];

        const tracyZ2 = ztracy.ZoneNC(@src(), "AcquireImage", 0xFF0000FF);
        if (try self.swapchain.acquireImage(self.context.gpi, frame) == false) {
            try self.renewSwapchain();
            return;
        }
        tracyZ2.End();

        const tracyZ3 = ztracy.ZoneNC(@src(), "recComputeCmd", 0x00A86BFF);
        try recordComputeCmdBuffer(
            &self.swapchain,
            frame.cmdBuff,
            frame.index,
            &self.pipelineMan.compute,
            self.descriptorManager.sets[frame.index],
        );
        tracyZ3.End();

        const tracyZ4 = ztracy.ZoneNC(@src(), "submitFrame", 0x800080FF);
        try self.pacer.submitFrame(self.context.graphicsQ, frame, self.swapchain.swapBuckets[frame.index].rendSem);
        tracyZ4.End();

        const tracyZ5 = ztracy.ZoneNC(@src(), "Present", 0xFFC0CBFF);
        if (try self.swapchain.present(self.context.presentQ, frame)) {
            try self.renewSwapchain();
            return;
        }
        tracyZ5.End();

        self.pacer.nextFrame();
    }

    pub fn checkShaderUpdate(self: *Renderer) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        const timeStamp = try getFileTimeStamp("src/shader/shdr.frag");
        if (timeStamp != self.fragmentTimeStemp) {
            self.fragmentTimeStemp = timeStamp;
            try self.updateGraphics();
            std.debug.print("Shader Updated ^^\n", .{});
            return;
        }
        tracyZ1.End();
    }

    pub fn checkComputeShaderUpdate(self: *Renderer) !void {
        const tracyZ1 = ztracy.ZoneNC(@src(), "checkShaderUpdate", 0x0000FFFF);
        const timeStamp = try getFileTimeStamp("src/shader/shdr.comp");
        if (timeStamp != self.computeTimeStemp) {
            self.computeTimeStemp = timeStamp;
            try self.updateCompute();
            std.debug.print("Shader Updated ^^\n", .{});
            return;
        }
        tracyZ1.End();
    }

    pub fn renewSwapchain(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.swapchain = try Swapchain.init(&self.resourceMan, self.alloc, &self.context, self.extentPtr);
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn updateCompute(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.pipelineMan.refreshComputePipeline(self.alloc, self.context.gpi);
    }

    pub fn updateGraphics(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.pipelineMan.refreshGraphicsPipeline(self.alloc, self.context.gpi);
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.pacer.deinit(self.alloc, self.context.gpi);
        self.cmdMan.deinit(self.context.gpi);
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.resourceMan.deinit();
        self.descriptorManager.deinit(self.context.gpi);
        self.pipelineMan.deinit(self.context.gpi);
        self.context.deinit();
    }
};

pub fn getFileTimeStamp(src: []const u8) !i128 {
    const cwd = std.fs.cwd();
    const stat = try cwd.statFile(src);
    const lastModified: i128 = stat.mtime;
    return lastModified;
}
