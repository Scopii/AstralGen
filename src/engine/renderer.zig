const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

const check = @import("error.zig").check;

const Context = @import("render/Context.zig").Context;
const createInstance = @import("render/Context.zig").createInstance;
const createSurface = @import("render/Context.zig").createSurface;
const getSurfaceCaps = @import("render/Context.zig").getSurfaceCaps;
const Swapchain = @import("render/Swapchain.zig").Swapchain;
const FramePacer = @import("sync/FramePacer.zig").FramePacer;
const VkAllocator = @import("vma.zig").VkAllocator;
const CmdManager = @import("render/CmdManager.zig").CmdManager;
const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const PipelineType = @import("render/PipelineBucket.zig").PipelineType;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;
const RenderImage = @import("render/ResourceManager.zig").RenderImage;
const VulkanWindow = @import("../core/VulkanWindow.zig").VulkanWindow;

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    surface: c.VkSurfaceKHR,
    context: Context,
    resourceMan: ResourceManager,
    descriptorManager: DescriptorManager,
    pipelineMan: PipelineManager,
    swapchain: Swapchain,
    cmdMan: CmdManager,
    pacer: FramePacer,
    descriptorsUpToDate: bool = false,
    usableFramesInFlight: u8 = 0,
    renderImage: RenderImage,

    window: VulkanWindow,

    pub fn init(alloc: Allocator, window: VulkanWindow, extent: c.VkExtent2D) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE); // stored in context
        const surface = try createSurface(window.handle, instance);
        const context = try Context.init(alloc, instance, surface);

        const resourceMan = try ResourceManager.init(&context);
        const cmdMan = try CmdManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pacer = try FramePacer.init(alloc, &context, MAX_IN_FLIGHT);
        const descriptorManager = try DescriptorManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pipelineMan = try PipelineManager.init(alloc, &context, &descriptorManager);

        const swapchain = try Swapchain.init(alloc, &context, surface, extent);
        const renderImage = try resourceMan.createRenderImage(extent);

        return .{
            .alloc = alloc,
            .surface = surface,
            .context = context,
            .resourceMan = resourceMan,
            .descriptorManager = descriptorManager,
            .pipelineMan = pipelineMan,
            .swapchain = swapchain,
            .cmdMan = cmdMan,
            .pacer = pacer,
            .renderImage = renderImage,
            .window = window,
        };
    }

    pub fn draw(self: *Renderer) !void {
        try self.pipelineMan.checkShaderUpdate(self.window.pipeType);
        try self.pacer.waitForGPU(self.context.gpi); // Waits if Frames in Flight limit is reached

        if (self.swapchain.acquireImage(self.context.gpi, self.pacer.getAcquisitionSemaphore()) == error.NeedNewSwapchain) {
            std.debug.print("Acquire Image failed\n", .{});
            const caps = try getSurfaceCaps(self.context.gpu, self.surface);
            try self.renewSwapchain(caps.currentExtent);
            self.pacer.nextFrame();
            return;
        }

        try self.pacer.submitFrame(self.context.graphicsQ, try self.decideCmd(self.window.pipeType), self.swapchain.getCurrentRenderSemaphore());
        if (self.swapchain.present(self.context.presentQ) == error.NeedNewSwapchain) {
            std.debug.print("Presentation failed\n", .{});
            const caps = try getSurfaceCaps(self.context.gpu, self.surface);
            try self.renewSwapchain(caps.currentExtent);
        }
        self.pacer.nextFrame();
    }

    fn decideCmd(self: *Renderer, pipeType: PipelineType) !c.VkCommandBuffer {
        if (self.usableFramesInFlight == MAX_IN_FLIGHT) return self.cmdMan.getCmd(self.pacer.curFrame);

        try self.cmdMan.beginRecording(self.pacer.curFrame);

        if (pipeType == .compute) {
            if (!self.descriptorsUpToDate) self.updateDescriptors();
            try self.cmdMan.recComputeCmd(&self.swapchain, &self.renderImage, &self.pipelineMan.compute, self.descriptorManager.sets[self.pacer.curFrame]);
        } else {
            try self.cmdMan.recRenderingCmd(&self.swapchain, &self.renderImage, if (pipeType == .mesh) &self.pipelineMan.mesh else &self.pipelineMan.graphics, pipeType);
        }

        self.usableFramesInFlight += 1;
        return try self.cmdMan.endRecording();
    }

    fn updateDescriptors(self: *Renderer) void {
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.renderImage.view);
        self.descriptorsUpToDate = true;
    }

    pub fn renewSwapchain(self: *Renderer, extent: c.VkExtent2D) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.swapchain.deinit(self.context.gpi);
        self.swapchain = try Swapchain.init(self.alloc, &self.context, self.surface, extent);
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.renderImage.view);
        self.invalidateFrames();
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn invalidateFrames(self: *Renderer) void {
        self.usableFramesInFlight = 0;
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);

        self.resourceMan.destroyRenderImage(self.renderImage);

        self.pacer.deinit(self.alloc, self.context.gpi);
        self.cmdMan.deinit(self.context.gpi);
        self.swapchain.deinit(self.context.gpi);
        self.resourceMan.deinit();
        self.descriptorManager.deinit(self.context.gpi);
        self.pipelineMan.deinit();
        c.vkDestroySurfaceKHR(self.context.instance, self.surface, null);
        self.context.deinit();
    }
};
