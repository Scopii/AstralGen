const std = @import("std");
const c = @import("../c.zig");
const DEBUG_TOGGLE = @import("../settings.zig").DEBUG_TOGGLE;
const check = @import("error.zig").check;
const Context = @import("render/Context.zig").Context;
const createInstance = @import("render/Context.zig").createInstance;
const SwapchainManager = @import("render/SwapchainManager.zig").SwapchainManager;
const Swapchain = @import("render/SwapchainManager.zig").Swapchain;
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
    pipeType: PipelineType,
    swapchain: *const Swapchain,
    imageIndex: u32,
    renderDoneSemaphore: c.VkSemaphore,
    imageRdySemaphore: c.VkSemaphore,
};

pub const MAX_IN_FLIGHT: u8 = 1;
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

    pub fn init(alloc: Allocator) !Renderer {
        const instance = try createInstance(alloc, DEBUG_TOGGLE);
        const context = try Context.init(alloc, instance);
        const resourceMan = try ResourceManager.init(&context);
        const cmdMan = try CmdManager.init(alloc, &context, MAX_IN_FLIGHT);
        const scheduler = try Scheduler.init(&context, MAX_IN_FLIGHT);
        const descriptorMan = try DescriptorManager.init(alloc, &context, MAX_IN_FLIGHT);
        const pipelineMan = try PipelineManager.init(alloc, &context, &descriptorMan);
        const renderImage = try resourceMan.createRenderImage(c.VkExtent2D{ .width = 1920, .height = 1080 });
        const swapchainMan = try SwapchainManager.init(alloc, &context);

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

    fn acquireImages() !void {}

    pub fn draw(self: *Renderer, windows: []*VulkanWindow) !void {
        try self.scheduler.waitForGPU();
        defer self.scheduler.nextFrame();

        const alloc = self.alloc;
        const frameInFlight = self.scheduler.frameInFlight;

        var presentTargets = std.ArrayList(PresentData).init(alloc);
        defer presentTargets.deinit();

        // In Renderer.draw
        for (windows) |window| {
            // This is the fix. `swapchain_ptr` is now a stable pointer to the
            // swapchain that lives inside the `window` struct.
            if (window.swapchain) |*swapchain_ptr| {
                var imageIndex: u32 = 0;
                const imageReadySem = swapchain_ptr.imageRdySemaphores[frameInFlight];
                const acquireResult = c.vkAcquireNextImageKHR(self.context.gpi, swapchain_ptr.handle, std.math.maxInt(u64), imageReadySem, null, &imageIndex);

                switch (acquireResult) {
                    c.VK_SUCCESS => {
                        try presentTargets.append(PresentData{
                            .pipeType = window.pipeType,
                            .swapchain = swapchain_ptr,
                            .imageIndex = imageIndex,
                            .renderDoneSemaphore = swapchain_ptr.renderDoneSemaphores[imageIndex],
                            .imageRdySemaphore = imageReadySem,
                        });
                    },
                    c.VK_ERROR_OUT_OF_DATE_KHR, c.VK_SUBOPTIMAL_KHR => return,
                    else => try check(acquireResult, "Could not acquire swapchain image"),
                }
            } else {
                return error.NoSwapchainToDrawTo;
            }
        }
        if (presentTargets.items.len == 0) return;

        const enumLength = @typeInfo(PipelineType).@"enum".fields.len;
        var groupedTargets: [enumLength]std.ArrayList(AcquiredImage) = undefined;
        for (0..enumLength) |i| groupedTargets[i] = std.ArrayList(AcquiredImage).init(alloc);
        defer for (0..enumLength) |i| groupedTargets[i].deinit();

        for (presentTargets.items) |target| {
            const acqImg = AcquiredImage{ .swapchain = target.swapchain, .imageIndex = target.imageIndex };
            try groupedTargets[@intFromEnum(target.pipeType)].append(acqImg);
        }

        try self.cmdMan.beginRecording(frameInFlight);

        for (0..groupedTargets.len) |i| {
            if (groupedTargets[i].items.len != 0) try self.recordCommands(groupedTargets[i].items, @enumFromInt(i), frameInFlight);
        }

        const cmd = try self.cmdMan.endRecording();

        try self.queueSubmit(cmd, presentTargets.items);
        try self.present(presentTargets.items);
    }

    fn recordCommands(self: *Renderer, targets: []const AcquiredImage, pipeType: PipelineType, frameInFlight: u8) !void {
        switch (pipeType) {
            .compute => {
                if (!self.descriptorsUpToDate) self.updateDescriptors();
                try self.cmdMan.recordComputePass(&self.renderImage, &self.pipelineMan.compute, self.descriptorMan.sets[frameInFlight]);
            },
            .graphics => try self.cmdMan.recordGraphicsPass(&self.renderImage, &self.pipelineMan.graphics, .graphics),
            .mesh => try self.cmdMan.recordGraphicsPass(&self.renderImage, &self.pipelineMan.mesh, .mesh),
        }
        try self.cmdMan.blitToTargets(&self.renderImage, targets);
    }

    fn queueSubmit(self: *Renderer, cmd: c.VkCommandBuffer, presentTargets: []const PresentData) !void {
        var waitInfos = try self.alloc.alloc(c.VkSemaphoreSubmitInfo, presentTargets.len);
        defer self.alloc.free(waitInfos);

        for (presentTargets, 0..) |target, i| {
            waitInfos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = target.imageRdySemaphore,
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            };
        }

        var signalInfos = try self.alloc.alloc(c.VkSemaphoreSubmitInfo, presentTargets.len + 1); // (+1 is Timeline Semaphore)
        defer self.alloc.free(signalInfos);

        for (presentTargets, 0..) |target, i| {
            signalInfos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = target.renderDoneSemaphore,
                .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            };
        }

        // Adding the timeline
        signalInfos[presentTargets.len] = .{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
            .semaphore = self.scheduler.cpuSyncTimeline,
            .value = self.scheduler.totalFrames + 1,
            .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        };

        const cmdInfo = c.VkCommandBufferSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
            .commandBuffer = cmd,
        };
        const submitInfo = c.VkSubmitInfo2{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(waitInfos.len),
            .pWaitSemaphoreInfos = waitInfos.ptr,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdInfo,
            .signalSemaphoreInfoCount = @intCast(signalInfos.len),
            .pSignalSemaphoreInfos = signalInfos.ptr,
        };
        try check(c.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInfo, null), "Failed main submission");
    }

    fn present(self: *Renderer, presentTargets: []const PresentData) !void {
        var swapchainHandles = try self.alloc.alloc(c.VkSwapchainKHR, presentTargets.len);
        defer self.alloc.free(swapchainHandles);
        var imageIndices = try self.alloc.alloc(u32, presentTargets.len);
        defer self.alloc.free(imageIndices);
        var presentWaitSems = try self.alloc.alloc(c.VkSemaphore, presentTargets.len);
        defer self.alloc.free(presentWaitSems);

        for (presentTargets, 0..) |target, i| {
            swapchainHandles[i] = target.swapchain.handle;
            imageIndices[i] = target.imageIndex;
            presentWaitSems[i] = target.renderDoneSemaphore;
        }

        const presentInfo = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = @intCast(presentWaitSems.len),
            .pWaitSemaphores = presentWaitSems.ptr,
            .swapchainCount = @intCast(swapchainHandles.len),
            .pSwapchains = swapchainHandles.ptr,
            .pImageIndices = imageIndices.ptr,
        };
        const result = c.vkQueuePresentKHR(self.context.presentQ, &presentInfo);
        if (result != c.VK_SUCCESS and result != c.VK_ERROR_OUT_OF_DATE_KHR and result != c.VK_SUBOPTIMAL_KHR) {
            try check(result, "Failed to present swapchain image");
        }
    }

    fn updateDescriptors(self: *Renderer) void {
        self.descriptorMan.updateAllDescriptorSets(self.renderImage.view);
        self.descriptorsUpToDate = true;
    }

    pub fn addWindow(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        //std.debug.print("Empty handle {?}", .{window.swapchain.?.handle});
        try self.swapchainMan.addSwapchain(&self.context, window, null);
    }

    pub fn renewSwapchain(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.swapchainMan.addSwapchain(&self.context, window, window.swapchain.?.handle);
        std.debug.print("Swapchain for window {} recreated\n", .{window.id});
    }

    pub fn updateRenderImageSize(self: *Renderer, windows: []const *VulkanWindow) !void {
        var maxWidth: u32 = 0;
        var maxHeight: u32 = 0;
        // Find the maximum dimensions required by any current window.
        for (windows) |window| {
            maxWidth = @max(maxWidth, window.extent.width);
            maxHeight = @max(maxHeight, window.extent.height);
        }

        // If no windows exist, default to a small size.
        if (maxWidth == 0 or maxHeight == 0) {
            maxWidth = 1;
            maxHeight = 1;
        }

        // If the optimal size is different from the current size, resize.
        if (maxWidth != self.renderImage.extent3d.width or maxHeight != self.renderImage.extent3d.height) {
            _ = c.vkDeviceWaitIdle(self.context.gpi);
            self.resourceMan.destroyRenderImage(self.renderImage);
            self.renderImage = try self.resourceMan.createRenderImage(.{ .width = maxWidth, .height = maxHeight });
            self.descriptorsUpToDate = false; // Descriptors are now stale.
            std.debug.print("renderImage now {}x{}\n", .{ maxWidth, maxHeight });
        }
    }

    pub fn destroyWindow(self: *Renderer, window: *VulkanWindow) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.swapchainMan.destroySwapchain(window);
        self.updateDescriptors();
    }
};
