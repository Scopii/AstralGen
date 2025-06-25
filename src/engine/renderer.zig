const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

const check = @import("error.zig").check;

const Context = @import("render/Context.zig").Context;
const Swapchain = @import("render/Swapchain.zig").Swapchain;
const FramePacer = @import("sync/FramePacer.zig").FramePacer;
const VkAllocator = @import("vma.zig").VkAllocator;
const CmdManager = @import("render/CmdManager.zig").CmdManager;
const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const PipelineType = @import("render/PipelineBucket.zig").PipelineType;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    descriptorManager: DescriptorManager,
    pipelineMan: PipelineManager,
    swapchain: Swapchain,
    cmdMan: CmdManager,
    pacer: FramePacer,
    descriptorsUpdated: bool,

    pub fn init(alloc: Allocator, window: *c.SDL_Window, extent: c.VkExtent2D) !Renderer {
        const context = try Context.init(alloc, window, DEBUG_TOGGLE);
        const resourceMan = try ResourceManager.init(&context);
        const swapchain = try Swapchain.init(alloc, &resourceMan, &context, extent, try context.getSurfaceCaps());
        const descriptorManager = try DescriptorManager.init(alloc, &context, @intCast(swapchain.swapBuckets.len));
        const pipelineMan = try PipelineManager.init(alloc, &context, &descriptorManager, swapchain.surfaceFormat.format);
        const cmdMan = try CmdManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pacer = try FramePacer.init(alloc, &context, MAX_IN_FLIGHT);

        return .{
            .alloc = alloc,
            .context = context,
            .resourceMan = resourceMan,
            .descriptorManager = descriptorManager,
            .pipelineMan = pipelineMan,
            .swapchain = swapchain,
            .cmdMan = cmdMan,
            .pacer = pacer,
            .descriptorsUpdated = false,
        };
    }

    pub fn draw(self: *Renderer, pipeline: PipelineType) !void {
        try self.pipelineMan.checkShaderUpdate(pipeline);

        try self.pacer.waitForGPU(self.context.gpi);

        const frameIndex = self.pacer.curFrame;
        const cmd = self.cmdMan.cmds[frameIndex];

        if (try self.swapchain.acquireImage(self.context.gpi, self.pacer.acqSems[frameIndex]) == false) {
            try self.renewSwapchain();
            self.pacer.nextFrame();
            return;
        }

        if (pipeline == .compute) {
            // Update descriptors only once when first needed
            if (!self.descriptorsUpdated) {
                self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
                self.descriptorsUpdated = true;
            }
        }

        const swapIndex = self.swapchain.index;
        const rendSem = self.swapchain.swapBuckets[swapIndex].rendSem;

        switch (pipeline) {
            .graphics => try self.cmdMan.recCmd(cmd, &self.swapchain, &self.pipelineMan.graphics),
            .compute => try self.cmdMan.recComputeCmd(cmd, &self.swapchain, &self.pipelineMan.compute, self.descriptorManager.sets[swapIndex]),
            .mesh => try self.cmdMan.recMeshCmd(cmd, &self.swapchain, &self.pipelineMan.mesh),
        }

        try self.pacer.submitFrame(self.context.graphicsQ, cmd, rendSem);
        if (try self.swapchain.present(self.context.presentQ, rendSem)) {
            try self.renewSwapchain();
        }
        self.pacer.nextFrame();
    }

    pub fn renewSwapchain(self: *Renderer) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        const caps = try self.context.getSurfaceCaps();
        const newExtent = caps.currentExtent;
        //std.debug.print("Caps Extent {}\n", .{caps.maxImageExtent});
        if (newExtent.width == 0 or newExtent.height == 0) {
            var event: c.SDL_Event = undefined;
            _ = c.SDL_WaitEvent(&event);
            return;
        }
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.swapchain = try Swapchain.init(self.alloc, &self.resourceMan, &self.context, newExtent, caps);
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.swapchain.renderImage.view);
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.pacer.deinit(self.alloc, self.context.gpi);
        self.cmdMan.deinit(self.context.gpi);
        self.swapchain.deinit(self.context.gpi, &self.resourceMan);
        self.resourceMan.deinit();
        self.descriptorManager.deinit(self.context.gpi);
        self.pipelineMan.deinit();
        self.context.deinit();
    }
};
