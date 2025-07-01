const std = @import("std");
const c = @import("../c.zig");
const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;
const check = @import("error.zig").check;
const Context = @import("render/Context.zig").Context;
const createInstance = @import("render/Context.zig").createInstance;
const createSurface = @import("render/Context.zig").createSurface;
const SwapchainManager = @import("render/SwapchainManager.zig").SwapchainManager;
const Swapchain = @import("render/SwapchainManager.zig").SwapchainManager.Swapchain;
const Scheduler = @import("render/Scheduler.zig").Scheduler;
const CmdManager = @import("render/CmdManager.zig").CmdManager;
const PipelineManager = @import("render/PipelineManager.zig").PipelineManager;
const PipelineType = @import("render/PipelineBucket.zig").PipelineType;
const ResourceManager = @import("render/ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("render/DescriptorManager.zig").DescriptorManager;
const RenderImage = @import("render/ResourceManager.zig").RenderImage;
const VulkanWindow = @import("../core/VulkanWindow.zig").VulkanWindow;

pub const AcquiredImage = struct {
    swapchain: *const Swapchain,
    imageIndex: u32,
};

const PresentData = struct {
    swapchain: *const Swapchain,
    imageIndex: u32,
    renderDoneSemaphore: c.VkSemaphore,
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
    renderImage: RenderImage,
    descriptorsUpToDate: bool = false,

    pub fn init(alloc: Allocator, window: *VulkanWindow) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const surface = try createSurface(window.handle, instance);
        const context = try Context.init(alloc, instance, surface);
        const resourceMan = try ResourceManager.init(&context);
        const cmdMan = try CmdManager.init(alloc, &context, MAX_IN_FLIGHT);
        const scheduler = try Scheduler.init(&context, MAX_IN_FLIGHT);
        const descriptorMan = try DescriptorManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pipelineMan = try PipelineManager.init(alloc, &context, &descriptorMan);
        const renderImage = try resourceMan.createRenderImage(window.extent);
        var swapchainMan = try SwapchainManager.init(alloc, &context);
        try swapchainMan.addSwapchain(&context, surface, window.extent, window.id, window.pipeType);

        return .{ .alloc = alloc, .context = context, .resourceMan = resourceMan, .descriptorMan = descriptorMan, .pipelineMan = pipelineMan, .cmdMan = cmdMan, .scheduler = scheduler, .renderImage = renderImage, .swapchainMan = swapchainMan };
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

    pub fn draw(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
        const frameIndex = self.scheduler.frameInFlight;

        var presentTargets = std.ArrayList(PresentData).init(self.alloc);
        defer presentTargets.deinit();
        var waitSems = std.ArrayList(c.VkSemaphore).init(self.alloc);
        defer waitSems.deinit();
        var needsResize = false;

        for (self.swapchainMan.swapchains.items) |*sc| {
            var imageIndex: u32 = 0;
            const imageReadySem = sc.imageRdySemaphores[frameIndex];
            const acquireResult = c.vkAcquireNextImageKHR(self.context.gpi, sc.handle, std.math.maxInt(u64), imageReadySem, null, &imageIndex);

            if (acquireResult == c.VK_SUCCESS or acquireResult == c.VK_SUBOPTIMAL_KHR) {
                try waitSems.append(imageReadySem);
                try presentTargets.append(.{ .swapchain = sc, .imageIndex = imageIndex, .renderDoneSemaphore = sc.renderDoneSemaphores[imageIndex] });
            } else if (acquireResult == c.VK_ERROR_OUT_OF_DATE_KHR) {
                needsResize = true;
                break;
            } else {
                try check(acquireResult, "Could not acquire swapchain image");
            }
        }
        if (needsResize or presentTargets.items.len == 0) {
            self.scheduler.nextFrame();
            return;
        }

        try self.cmdMan.beginRecording(frameIndex);

        var computeTargets = std.ArrayList(AcquiredImage).init(self.alloc);
        defer computeTargets.deinit();
        var graphicsTargets = std.ArrayList(AcquiredImage).init(self.alloc);
        defer graphicsTargets.deinit();
        var meshTargets = std.ArrayList(AcquiredImage).init(self.alloc);
        defer meshTargets.deinit();

        for (presentTargets.items) |target| {
            const acqImg = AcquiredImage{ .swapchain = target.swapchain, .imageIndex = target.imageIndex };
            switch (target.swapchain.pipeType) {
                .compute => try computeTargets.append(acqImg),
                .graphics => try graphicsTargets.append(acqImg),
                .mesh => try meshTargets.append(acqImg),
            }
        }

        if (!self.descriptorsUpToDate) self.updateDescriptors();
        try self.cmdMan.recordComputePassAndBlit(&self.renderImage, &self.pipelineMan.compute, self.descriptorMan.sets[frameIndex]);
        try self.cmdMan.blitToTargets(&self.renderImage, computeTargets.items);
        try self.cmdMan.recordGraphicsPassAndBlit(&self.renderImage, &self.pipelineMan.graphics, .graphics);
        try self.cmdMan.blitToTargets(&self.renderImage, graphicsTargets.items);
        try self.cmdMan.recordGraphicsPassAndBlit(&self.renderImage, &self.pipelineMan.mesh, .mesh);
        try self.cmdMan.blitToTargets(&self.renderImage, meshTargets.items);

        const cmd = try self.cmdMan.endRecording();

        var signalSems = std.ArrayList(c.VkSemaphore).init(self.alloc);
        defer signalSems.deinit();
        for (presentTargets.items) |target| try signalSems.append(target.renderDoneSemaphore);
        try signalSems.append(self.scheduler.cpuSyncTimeline);

        var waitInfos = try self.alloc.alloc(c.VkSemaphoreSubmitInfo, waitSems.items.len);
        defer self.alloc.free(waitInfos);
        for (waitSems.items, 0..) |s, i| {
            waitInfos[i] = .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = s, .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT };
        }

        var signalInfos = try self.alloc.alloc(c.VkSemaphoreSubmitInfo, signalSems.items.len);
        defer self.alloc.free(signalInfos);
        for (signalSems.items, 0..) |s, i| {
            if (s == self.scheduler.cpuSyncTimeline) {
                signalInfos[i] = .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = s, .value = self.scheduler.frameCount + 1, .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT };
            } else {
                signalInfos[i] = .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = s, .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT };
            }
        }

        const cmdInfo = c.VkCommandBufferSubmitInfo{ .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = cmd };
        const submitInfo = c.VkSubmitInfo2{ .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2, .waitSemaphoreInfoCount = @intCast(waitInfos.len), .pWaitSemaphoreInfos = waitInfos.ptr, .commandBufferInfoCount = 1, .pCommandBufferInfos = &cmdInfo, .signalSemaphoreInfoCount = @intCast(signalInfos.len), .pSignalSemaphoreInfos = signalInfos.ptr };
        try check(c.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInfo, null), "Failed main submission");

        var swapchainHandles = try self.alloc.alloc(c.VkSwapchainKHR, presentTargets.items.len);
        defer self.alloc.free(swapchainHandles);
        var imageIndices = try self.alloc.alloc(u32, presentTargets.items.len);
        defer self.alloc.free(imageIndices);
        var presentWaitSems = try self.alloc.alloc(c.VkSemaphore, presentTargets.items.len);
        defer self.alloc.free(presentWaitSems);

        for (presentTargets.items, 0..) |target, i| {
            swapchainHandles[i] = target.swapchain.handle;
            imageIndices[i] = target.imageIndex;
            presentWaitSems[i] = target.renderDoneSemaphore;
        }

        const presentInfo = c.VkPresentInfoKHR{ .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR, .waitSemaphoreCount = @intCast(presentWaitSems.len), .pWaitSemaphores = presentWaitSems.ptr, .swapchainCount = @intCast(swapchainHandles.len), .pSwapchains = swapchainHandles.ptr, .pImageIndices = imageIndices.ptr };
        const result = c.vkQueuePresentKHR(self.context.presentQ, &presentInfo);
        if (result != c.VK_SUCCESS and result != c.VK_ERROR_OUT_OF_DATE_KHR and result != c.VK_SUBOPTIMAL_KHR) {
            try check(result, "Failed to present swapchain image");
        }

        self.scheduler.frameCount += 1;
        self.scheduler.nextFrame();
    }

    fn updateDescriptors(self: *Renderer) void {
        self.descriptorMan.updateAllDescriptorSets(self.renderImage.view);
        self.descriptorsUpToDate = true;
    }

    pub fn addWindow(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.updateRenderImageSize();
        const surface = try createSurface(window.handle, self.context.instance);
        try self.swapchainMan.addSwapchain(&self.context, surface, window.extent, window.id, window.pipeType);
    }

    pub fn renewSwapchain(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.swapchainMan.destroySwapchain(window.id);
        const surface = try createSurface(window.handle, self.context.instance);
        try self.swapchainMan.addSwapchain(&self.context, surface, window.extent, window.id, window.pipeType);
        try self.updateRenderImageSize();
        std.debug.print("Swapchain for window {} recreated\n", .{window.id});
    }

    fn updateRenderImageSize(self: *Renderer) !void {
        var maxWidth: u32 = 0;
        var maxHeight: u32 = 0;
        // Find the maximum dimensions required by any current window.
        for (self.swapchainMan.swapchains.items) |sc| {
            maxWidth = @max(maxWidth, sc.extent.width);
            maxHeight = @max(maxHeight, sc.extent.height);
        }

        // If no windows exist, default to a small size.
        if (maxWidth == 0 or maxHeight == 0) {
            maxWidth = 1;
            maxHeight = 1;
        }

        // If the optimal size is different from the current size, resize.
        if (maxWidth != self.renderImage.extent3d.width or maxHeight != self.renderImage.extent3d.height) {
            std.debug.print("Updating renderImage size to {}x{}\n", .{ maxWidth, maxHeight });
            _ = c.vkDeviceWaitIdle(self.context.gpi);
            self.resourceMan.destroyRenderImage(self.renderImage);
            self.renderImage = try self.resourceMan.createRenderImage(.{ .width = maxWidth, .height = maxHeight });
            self.descriptorsUpToDate = false; // Descriptors are now stale.
        }
    }

    pub fn destroyWindow(self: *Renderer, windowId: u32) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.swapchainMan.destroySwapchain(windowId);
        try self.updateRenderImageSize();
        self.updateDescriptors();
    }
};
