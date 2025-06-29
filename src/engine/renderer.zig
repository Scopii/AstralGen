const std = @import("std");
const c = @import("../c.zig");
const ztracy = @import("ztracy");

const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;

const check = @import("error.zig").check;

const Context = @import("render/Context.zig").Context;
const createInstance = @import("render/Context.zig").createInstance;
const createSurface = @import("render/Context.zig").createSurface;
const getSurfaceCaps = @import("render/Context.zig").getSurfaceCaps;
const SwapchainManager = @import("render/SwapchainManager.zig").SwapchainManager;
const Scheduler = @import("render/Scheduler.zig").Scheduler;
const VkAllocator = @import("vma.zig").VkAllocator;
const CmdManager = @import("render/CmdManager.zig").CmdManager;
const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const PipelineType = @import("render/PipelineBucket.zig").PipelineType;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;
const RenderImage = @import("render/ResourceManager.zig").RenderImage;
const VulkanWindow = @import("../core/VulkanWindow.zig").VulkanWindow;

const AcquiredImageInfo = struct {
    swapchain_index: u32,
    image_index: u32,
};

pub const MAX_IN_FLIGHT: u8 = 3;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    descriptorMan: DescriptorManager,
    pipelineMan: PipelineManager,
    swapchainMan: SwapchainManager,
    cmdMan: CmdManager,
    scheduler: Scheduler,
    descriptorsUpToDate: bool = false,
    usableFramesInFlight: u8 = 0,
    renderImage: RenderImage,

    pub fn init(alloc: Allocator, window: *VulkanWindow) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE); // stored in context
        const surface = try createSurface(window.handle, instance); // stored in Swapchain
        const context = try Context.init(alloc, instance, surface);

        const resourceMan = try ResourceManager.init(&context);
        const cmdMan = try CmdManager.init(alloc, &context, MAX_IN_FLIGHT);
        const scheduler = try Scheduler.init(&context, MAX_IN_FLIGHT);
        const descriptorMan = try DescriptorManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pipelineMan = try PipelineManager.init(alloc, &context, &descriptorMan);
        const renderImage = try resourceMan.createRenderImage(window.extent);

        var swapchainMan = try SwapchainManager.init(alloc, &context, MAX_IN_FLIGHT);
        try swapchainMan.addSwapchain(&context, surface, window.extent, window.id, window.pipeType);

        return .{
            .alloc = alloc,
            .context = context,
            .resourceMan = resourceMan,
            .descriptorMan = descriptorMan,
            .pipelineMan = pipelineMan,
            .cmdMan = cmdMan,
            .scheduler = scheduler,
            .renderImage = renderImage,
            .swapchainMan = swapchainMan,
        };
    }

    pub fn addWindow(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.checkRenderImageIncrease(window.extent);
        const surface = try createSurface(window.handle, self.context.instance); // Destroyed in Swapchain Manager
        try self.swapchainMan.addSwapchain(&self.context, surface, window.extent, window.id, window.pipeType);
    }

    pub fn checkRenderImageIncrease(self: *Renderer, extent: c.VkExtent2D) !void {
        const height = if (extent.height >= self.renderImage.extent3d.height) extent.height else self.renderImage.extent3d.height;
        const width = if (extent.width >= self.renderImage.extent3d.width) extent.width else self.renderImage.extent3d.width;
        self.resourceMan.destroyRenderImage(self.renderImage);
        self.renderImage = try self.resourceMan.createRenderImage(c.VkExtent2D{ .width = width, .height = height });
    }

    pub fn draw(self: *Renderer) !void {
        var acquiredImages = std.ArrayList(u32).init(self.alloc);
        defer acquiredImages.deinit();
        var waitSems = std.ArrayList(c.VkSemaphore).init(self.alloc);
        defer waitSems.deinit();
        var renderSems = std.ArrayList(c.VkSemaphore).init(self.alloc);
        defer renderSems.deinit();

        try self.scheduler.waitForGPU();
        const frameInFlight = self.scheduler.frameInFlight;
        try self.cmdMan.beginRecording(frameInFlight);

        for (self.swapchainMan.swapchains.items) |*swapchain| {
            // Acquire the image for this window
            const imageRdySem = swapchain.imageRdySemaphore[frameInFlight];
            var imageIndex: u32 = 0;
            const acquireResult = c.vkAcquireNextImageKHR(self.context.gpi, swapchain.handle, 1_000_000_000, imageRdySem, null, &imageIndex);

            if (acquireResult == c.VK_ERROR_OUT_OF_DATE_KHR or acquireResult == c.VK_SUBOPTIMAL_KHR) {
                // Handle resize here. For now, just skip.
                continue;
            }
            try check(acquireResult, "Could not acquire swapchain image");

            try waitSems.append(imageRdySem);

            // Record commands for this window INTO ACTIVE BUFFER.
            if (swapchain.pipeType == .compute) {
                if (!self.descriptorsUpToDate) self.updateDescriptors();
                try self.cmdMan.recComputeCmd(swapchain, imageIndex, &self.renderImage, &self.pipelineMan.compute, self.descriptorMan.sets[frameInFlight]);
            } else {
                // NOTE: Your recRenderingCmd still renders to renderImage and blits.
                try self.cmdMan.recRenderingCmd(swapchain, imageIndex, &self.renderImage, if (swapchain.pipeType == .mesh) &self.pipelineMan.mesh else &self.pipelineMan.graphics, swapchain.pipeType);
            }

            try renderSems.append(swapchain.renderDoneSemaphore[frameInFlight]);
            try acquiredImages.append(imageIndex);
        }

        const cmd = try self.cmdMan.endRecording();

        // Submit the command buffer. It waits for ALL images to be available. It signals ALL render done semaphores, PLUS the scheduler timeline.
        const waitStages = try self.alloc.alloc(c.VkPipelineStageFlags, waitSems.items.len);
        defer self.alloc.free(waitStages);
        for (waitStages) |*s| {
            s.* = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
        }

        // Add the scheduler's timeline to the signal list
        try renderSems.append(self.scheduler.cpuSyncTimeline);

        var waitInfList = std.ArrayList(c.VkSemaphoreSubmitInfo).init(self.alloc);
        defer waitInfList.deinit();
        for (waitSems.items) |sem| {
            try waitInfList.append(.{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = sem,
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            });
        }

        var signalInfList = std.ArrayList(c.VkSemaphoreSubmitInfo).init(self.alloc);
        defer signalInfList.deinit();
        for (renderSems.items, 0..) |sem, i| {
            if (i == renderSems.items.len - 1) { // This is the timeline semaphore
                try signalInfList.append(.{
                    .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                    .semaphore = sem,
                    .value = self.scheduler.frameCount + 1,
                    .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                });
            } else {
                try signalInfList.append(.{
                    .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                    .semaphore = sem,
                    .value = 0,
                    .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                });
            }
        }

        const submitInf = c.VkSubmitInfo2{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(waitInfList.items.len),
            .pWaitSemaphoreInfos = waitInfList.items.ptr,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &c.VkCommandBufferSubmitInfo{
                .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
                .commandBuffer = cmd,
                .deviceMask = 0,
            },
            .signalSemaphoreInfoCount = @intCast(signalInfList.items.len),
            .pSignalSemaphoreInfos = signalInfList.items.ptr,
        };
        try check(c.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInf, null), "Failed main submission");
        self.scheduler.frameCount += 1;

        // PRESENTATION LOOP:
        for (self.swapchainMan.swapchains.items, 0..) |*swapchain, i| {
            const imageIndex = acquiredImages.items[i];
            const presentInf = c.VkPresentInfoKHR{
                .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                .waitSemaphoreCount = 1,
                .pWaitSemaphores = &swapchain.renderDoneSemaphore[frameInFlight],
                .swapchainCount = 1,
                .pSwapchains = &swapchain.handle,
                .pImageIndices = &imageIndex,
            };
            _ = c.vkQueuePresentKHR(self.context.presentQ, &presentInf);
        }

        self.scheduler.nextFrame();
    }

    fn updateDescriptors(self: *Renderer) void {
        self.descriptorMan.updateAllDescriptorSets(self.renderImage.view);
        self.descriptorsUpToDate = true;
    }

    pub fn renewSwapchain(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.checkRenderImageIncrease(window.extent);

        try self.swapchainMan.destroySwapchain(window.id);
        const surface = try createSurface(window.handle, self.context.instance); // Destroyed in Swapchain Manager
        try self.swapchainMan.addSwapchain(&self.context, surface, window.extent, window.id, window.pipeType);

        self.updateDescriptors();
        self.invalidateFrames();
        std.debug.print("Swapchain recreated\n", .{});
    }

    pub fn destroyWindow(self: *Renderer, windowId: u32) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        const extent = try self.swapchainMan.getSwapchainExtent(windowId);
        try self.swapchainMan.destroySwapchain(windowId);
        const swapchainCount = self.swapchainMan.getSwapchainsCount();

        var width: u32 = 0;
        var height: u32 = 0;

        if (extent.height == self.renderImage.extent3d.height or extent.width == self.renderImage.extent3d.width) {
            if (swapchainCount < 1) return;
            for (self.swapchainMan.swapchains.items) |swapchain| {
                if (swapchain.extent.height > height) height = swapchain.extent.height;
                if (swapchain.extent.width > width) width = swapchain.extent.width;
            }
        } else {
            return;
        }
        std.debug.print("New Render Image {}x{}\n", .{ width, height });
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
        self.scheduler.deinit();
        self.cmdMan.deinit();
        self.swapchainMan.deinit();
        self.resourceMan.deinit();
        self.descriptorMan.deinit();
        self.pipelineMan.deinit();
        self.context.deinit();
    }
};
