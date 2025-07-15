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
const Window = @import("../core/Window.zig").Window;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;

pub const MAX_IN_FLIGHT: u8 = 3;
const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    descriptorMan: DescriptorManager,
    pipelineMan: PipelineManager,
    swapchainMan: SwapchainManager,
    cmdMan: CmdManager,
    scheduler: Scheduler,
    renderImage: RenderImage,
    descriptorsUpToDate: bool = false,

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();

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
            .arenaAlloc = memoryMan.getGlobalArena(),
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

    fn acquirePresentData() !void {}

    pub fn draw(self: *Renderer, swapchainPtrs: []*Swapchain) !void {
        try self.scheduler.waitForGPU();
        defer self.scheduler.nextFrame();

        const frameInFlight = self.scheduler.frameInFlight;

        const enumLength = @typeInfo(PipelineType).@"enum".fields.len;
        var presentTargets: [enumLength]std.ArrayList(*Swapchain) = undefined;
        for (0..enumLength) |i| presentTargets[i] = std.ArrayList(*Swapchain).init(self.arenaAlloc);

        var targetCount: u32 = 0;

        for (swapchainPtrs) |swapchainPtr| {
            const acquireResult = c.vkAcquireNextImageKHR(self.context.gpi, swapchainPtr.handle, std.math.maxInt(u64), swapchainPtr.imageRdySemaphores[frameInFlight], null, &swapchainPtr.curIndex);

            switch (acquireResult) {
                c.VK_SUCCESS => {
                    try presentTargets[@intFromEnum(swapchainPtr.pipeType)].append(swapchainPtr);
                    targetCount += 1;
                },
                c.VK_ERROR_OUT_OF_DATE_KHR, c.VK_SUBOPTIMAL_KHR => continue, //not handling error yet
                else => try check(acquireResult, "Could not acquire swapchain image"),
            }
        }
        if (targetCount == 0) return;

        try self.cmdMan.beginRecording(frameInFlight);
        for (0..presentTargets.len) |i| {
            if (presentTargets[i].items.len != 0) try self.recordCommands(presentTargets[i].items, @enumFromInt(i), frameInFlight);
        }
        const cmd = try self.cmdMan.endRecording();

        var allTargets = std.ArrayList(*Swapchain).init(self.arenaAlloc);
        try allTargets.ensureTotalCapacity(targetCount);
        for (presentTargets) |group| try allTargets.appendSlice(group.items);

        try self.queueSubmit(cmd, allTargets.items, frameInFlight);
        try self.present(allTargets.items);
    }

    fn recordCommands(self: *Renderer, targets: []const *Swapchain, pipeType: PipelineType, frameInFlight: u8) !void {
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

    fn queueSubmit(self: *Renderer, cmd: c.VkCommandBuffer, presentTargets: []const *Swapchain, frameInFlight: u8) !void {
        var waitInfos = try self.arenaAlloc.alloc(c.VkSemaphoreSubmitInfo, presentTargets.len);

        for (presentTargets, 0..) |swapchain, i| {
            waitInfos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = swapchain.imageRdySemaphores[frameInFlight],
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            };
        }

        var signalInfos = try self.arenaAlloc.alloc(c.VkSemaphoreSubmitInfo, presentTargets.len + 1); // (+1 is Timeline Semaphore)

        for (presentTargets, 0..) |swapchain, i| {
            signalInfos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = swapchain.renderDoneSemaphores[swapchain.curIndex],
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

    fn present(self: *Renderer, presentTargets: []const *Swapchain) !void {
        var swapchainHandles = try self.alloc.alloc(c.VkSwapchainKHR, presentTargets.len);
        defer self.alloc.free(swapchainHandles);
        var imageIndices = try self.alloc.alloc(u32, presentTargets.len);
        defer self.alloc.free(imageIndices);
        var presentWaitSems = try self.alloc.alloc(c.VkSemaphore, presentTargets.len);
        defer self.alloc.free(presentWaitSems);

        for (presentTargets, 0..) |swapchain, i| {
            swapchainHandles[i] = swapchain.handle;
            imageIndices[i] = swapchain.curIndex;
            presentWaitSems[i] = swapchain.renderDoneSemaphores[swapchain.curIndex];
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

    pub fn giveSwapchain(self: *Renderer, window: *Window, pipeType: PipelineType, wantedExtent: c.VkExtent2D) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.swapchainMan.addSwapchain(&self.context, window, null, pipeType, wantedExtent);
    }

    pub fn renewSwapchain(self: *Renderer, window: *Window, wantedExtent: c.VkExtent2D) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.swapchainMan.addSwapchain(&self.context, window, window.swapchain.?.handle, window.swapchain.?.pipeType, wantedExtent);
        std.debug.print("Swapchain for window {} recreated\n", .{window.id});
    }

    pub fn updateRenderImage(self: *Renderer, swapchains: []const *Swapchain) !void {
        var maxWidth: u32 = 0;
        var maxHeight: u32 = 0;

        for (swapchains) |swapchain| {
            maxWidth = @max(maxWidth, swapchain.extent.width);
            maxHeight = @max(maxHeight, swapchain.extent.height);
        }

        if (maxWidth != self.renderImage.extent3d.width or maxHeight != self.renderImage.extent3d.height) {
            _ = c.vkDeviceWaitIdle(self.context.gpi);
            self.resourceMan.destroyRenderImage(self.renderImage);
            self.renderImage = try self.resourceMan.createRenderImage(.{ .width = maxWidth, .height = maxHeight });
            self.descriptorsUpToDate = false;
            std.debug.print("renderImage now {}x{}\n", .{ maxWidth, maxHeight });
        }
    }

    pub fn destroyWindow(self: *Renderer, window: *Window) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.swapchainMan.destroySwapchain(window);
        self.updateDescriptors();
    }
};
