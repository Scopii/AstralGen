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

pub const WindowBucket = struct {
    window: *VulkanWindow,
    surface: c.VkSurfaceKHR,
    swapchain: Swapchain,

    pub fn init(window: *VulkanWindow, surface: c.VkSurfaceKHR, swapchain: Swapchain) WindowBucket {
        return .{
            .window = window,
            .surface = surface,
            .swapchain = swapchain,
        };
    }

    pub fn deinit(self: *WindowBucket, context: *Context) void {
        _ = c.vkDeviceWaitIdle(context.gpi);
        self.swapchain.deinit();
        c.vkDestroySurfaceKHR(context.instance, self.surface, null);
    }
};

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    surface: c.VkSurfaceKHR,
    context: Context,
    resourceMan: ResourceManager,
    descriptorManager: DescriptorManager,
    pipelineMan: PipelineManager,
    cmdMan: CmdManager,
    pacer: FramePacer,
    descriptorsUpToDate: bool = false,
    usableFramesInFlight: u8 = 0,
    renderImage: RenderImage,

    windowBuckets: std.AutoHashMap(u32, WindowBucket),

    pub fn init(alloc: Allocator, window: *VulkanWindow) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE); // stored in context
        const surface = try createSurface(window.handle, instance); // stored in Swapchain
        const context = try Context.init(alloc, instance, surface);

        const resourceMan = try ResourceManager.init(&context);
        const cmdMan = try CmdManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pacer = try FramePacer.init(alloc, &context, MAX_IN_FLIGHT);
        const descriptorManager = try DescriptorManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pipelineMan = try PipelineManager.init(alloc, &context, &descriptorManager);
        const renderImage = try resourceMan.createRenderImage(window.extent);

        const swapchain = try Swapchain.init(alloc, &context, surface, window.extent);

        var windowBuckets = std.AutoHashMap(u32, WindowBucket).init(alloc);
        const windowBucket = WindowBucket.init(window, surface, swapchain);
        try windowBuckets.put(window.id, windowBucket);

        return .{
            .alloc = alloc,
            .surface = surface,
            .context = context,
            .resourceMan = resourceMan,
            .descriptorManager = descriptorManager,
            .pipelineMan = pipelineMan,
            .cmdMan = cmdMan,
            .pacer = pacer,
            .renderImage = renderImage,
            .windowBuckets = windowBuckets,
        };
    }

    pub fn addWindow(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.checkRenderImageIncrease(window.extent);
        const surface = try createSurface(window.handle, self.context.instance);
        const swapchain = try Swapchain.init(self.alloc, &self.context, surface, window.extent);
        const windowBucket = WindowBucket.init(window, surface, swapchain);
        try self.windowBuckets.put(window.id, windowBucket);
    }

    pub fn checkRenderImageIncrease(self: *Renderer, extent: c.VkExtent2D) !void {
        const height = if (extent.height >= self.renderImage.extent3d.height) extent.height else self.renderImage.extent3d.height;
        const width = if (extent.width >= self.renderImage.extent3d.width) extent.width else self.renderImage.extent3d.width;

        self.resourceMan.destroyRenderImage(self.renderImage);
        self.renderImage = try self.resourceMan.createRenderImage(c.VkExtent2D{ .width = width, .height = height });
    }

    pub fn draw(self: *Renderer) !void {
        self.invalidateFrames();

        var iter = self.windowBuckets.valueIterator();
        while (iter.next()) |bucket| {
            try self.pipelineMan.checkShaderUpdate(bucket.window.pipeType);
            try self.pacer.waitForGPU(self.context.gpi); // Waits if Frames in Flight limit is reached

            if (bucket.swapchain.acquireImage(self.pacer.getAcquisitionSemaphore()) == error.NeedNewSwapchain) {
                std.debug.print("Acquire Image failed\n", .{});
                const caps = try getSurfaceCaps(self.context.gpu, bucket.surface);
                try self.renewSwapchain(caps.currentExtent, bucket.window.id);
                self.pacer.nextFrame();
                return;
            }

            try self.pacer.submitFrame(self.context.graphicsQ, try self.decideCmd(bucket), bucket.swapchain.getCurrentRenderSemaphore());
            if (bucket.swapchain.present(self.context.presentQ) == error.NeedNewSwapchain) {
                std.debug.print("Presentation failed\n", .{});
                const caps = try getSurfaceCaps(self.context.gpu, bucket.surface);
                try self.renewSwapchain(caps.currentExtent, bucket.window.id);
            }
            self.pacer.nextFrame();
        }
    }

    fn decideCmd(self: *Renderer, windowBucket: *const WindowBucket) !c.VkCommandBuffer {
        if (self.usableFramesInFlight == MAX_IN_FLIGHT) return self.cmdMan.getCmd(self.pacer.curFrame);

        try self.cmdMan.beginRecording(self.pacer.curFrame);

        const pipeType = windowBucket.window.pipeType;

        if (pipeType == .compute) {
            if (!self.descriptorsUpToDate) self.updateDescriptors();
            try self.cmdMan.recComputeCmd(&windowBucket.swapchain, &self.renderImage, &self.pipelineMan.compute, self.descriptorManager.sets[self.pacer.curFrame]);
        } else {
            try self.cmdMan.recRenderingCmd(&windowBucket.swapchain, &self.renderImage, if (pipeType == .mesh) &self.pipelineMan.mesh else &self.pipelineMan.graphics, pipeType);
        }

        self.usableFramesInFlight += 1;
        return try self.cmdMan.endRecording();
    }

    fn updateDescriptors(self: *Renderer) void {
        self.descriptorManager.updateAllDescriptorSets(self.context.gpi, self.renderImage.view);
        self.descriptorsUpToDate = true;
    }

    pub fn renewSwapchain(self: *Renderer, extent: c.VkExtent2D, id: u32) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.checkRenderImageIncrease(extent);
        const bucket = self.windowBuckets.getPtr(id) orelse {
            std.log.err("renewSwapchain failed: Could not find window with ID {}\n", .{id});
            return error.WindowNotFound;
        };
        bucket.swapchain.deinit();
        bucket.swapchain = try Swapchain.init(self.alloc, &self.context, bucket.surface, extent);
        self.updateDescriptors();
        self.invalidateFrames();
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn destroyWindow(self: *Renderer, id: u32) !void {
        const bucket = self.windowBuckets.getPtr(id) orelse {
            std.log.err("renewSwapchain failed: Could not find window with ID {}\n", .{id});
            return error.WindowNotFound;
        };
        const extent = bucket.window.extent;
        bucket.deinit(&self.context);
        _ = self.windowBuckets.remove(id);

        var width: u32 = 0;
        var height: u32 = 0;

        if (extent.height == self.renderImage.extent3d.height or extent.width == self.renderImage.extent3d.width) {
            if (self.windowBuckets.count() < 1) return;
            var iter = self.windowBuckets.valueIterator();
            while (iter.next()) |testBucket| {
                if (testBucket.window.extent.height > height) height = testBucket.window.extent.height;
                if (testBucket.window.extent.width > width) width = testBucket.window.extent.width;
            }
        } else {
            return;
        }

        self.resourceMan.destroyRenderImage(self.renderImage);
        self.renderImage = try self.resourceMan.createRenderImage(c.VkExtent2D{ .width = width, .height = height });
        self.updateDescriptors();
    }

    pub fn invalidateFrames(self: *Renderer) void {
        self.usableFramesInFlight = 0;
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);

        self.resourceMan.destroyRenderImage(self.renderImage);

        self.pacer.deinit(self.alloc, self.context.gpi);
        self.cmdMan.deinit(self.context.gpi);

        var iter = self.windowBuckets.valueIterator();
        while (iter.next()) |bucket| {
            bucket.deinit(&self.context);
        }
        self.windowBuckets.deinit();

        self.resourceMan.deinit();
        self.descriptorManager.deinit(self.context.gpi);
        self.pipelineMan.deinit();
        self.context.deinit();
    }
};
