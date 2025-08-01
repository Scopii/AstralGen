const std = @import("std");
const c = @import("../c.zig");
const check = @import("error.zig").check;
const Context = @import("Context.zig").Context;
const createInstance = @import("Context.zig").createInstance;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const Swapchain = @import("SwapchainManager.zig").Swapchain;
const Scheduler = @import("Scheduler.zig").Scheduler;
const CmdManager = @import("CmdManager.zig").CmdManager;
const PipelineManager = @import("PipelineManager.zig").PipelineManager;
const PipelineType = @import("PipelineBucket.zig").PipelineType;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const DescriptorManager = @import("DescriptorManager.zig").DescriptorManager;
const RenderImage = @import("ResourceManager.zig").RenderImage;
const Window = @import("../platform/Window.zig").Window;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const MAX_IN_FLIGHT = @import("../config.zig").MAX_IN_FLIGHT;
const SHADER_HOTLOAD = @import("../config.zig").SHADER_HOTLOAD;
const DEBUG_TOGGLE = @import("../config.zig").DEBUG_TOGGLE;

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

    pub fn update(self: *Renderer, windows: []*Window) !void {
        for (windows) |window| {
            if (window.status == .needDelete or window.status == .needUpdate) {
                _ = c.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }

        for (windows) |window| {
            stateSwitch: switch (window.status) {
                .needUpdate => {
                    if (self.swapchainMan.getSwapchainPtr(window.id) != null) {
                        self.swapchainMan.destroySwapchains(&.{window.*});
                        continue :stateSwitch .needCreation;
                    }
                },
                .needActive => {
                    try self.swapchainMan.addActive(window.*);
                    window.status = .active;
                },
                .needInactive => {
                    self.swapchainMan.removeActive(window.*);
                    window.status = .inactive;
                },
                .needCreation => {
                    try self.swapchainMan.addSwapchain(&self.context, window.*);
                    window.status = .active;
                },
                .needDelete => {
                    self.swapchainMan.destroySwapchains(&.{window.*});
                },
                else => std.debug.print("invalid window State for Renderer\n", .{}),
            }
        }
        try self.updateDescriptors();

        try self.swapchainMan.updateRenderSize();

        const renderSize = self.swapchainMan.getRenderSize();

        if (renderSize.height != 0 or renderSize.width != 0) {
            if (renderSize.width != self.renderImage.extent3d.width or renderSize.height != self.renderImage.extent3d.height) {
                self.resourceMan.destroyRenderImage(self.renderImage);
                self.renderImage = try self.resourceMan.createRenderImage(.{ .width = renderSize.width, .height = renderSize.height });
                self.descriptorsUpToDate = false;
                std.debug.print("renderImage now {}x{}\n", .{ renderSize.width, renderSize.height });
            }
        }
    }

    pub fn draw(self: *Renderer) !void {
        try self.scheduler.waitForGPU();

        const frameInFlight = self.scheduler.frameInFlight;
        if (try self.swapchainMan.updateTargets(frameInFlight, &self.context) == false) return;

        try self.cmdMan.beginRecording(frameInFlight);
        const activeSwapchains = self.swapchainMan.activeGroups;

        for (0..activeSwapchains.len) |i| {
            if (activeSwapchains[i].len != 0) {
                const renderPass: PipelineType = @enumFromInt(i);
                if (SHADER_HOTLOAD == true) try self.pipelineMan.checkShaderUpdate(renderPass);
                try self.recordCommands(activeSwapchains[i].slice(), renderPass, frameInFlight);
            }
        }
        const cmd = try self.cmdMan.endRecording();

        const targets = self.swapchainMan.targets.slice();
        try self.queueSubmit(cmd, targets, frameInFlight);
        try self.present(targets);

        self.scheduler.nextFrame();
    }

    fn recordCommands(self: *Renderer, recordIds: []const u8, pipeType: PipelineType, frameInFlight: u8) !void {
        switch (pipeType) {
            .compute => {
                if (!self.descriptorsUpToDate) try self.updateDescriptors();
                try self.cmdMan.recordComputePass(&self.renderImage, &self.pipelineMan.compute, self.descriptorMan.sets[frameInFlight]);
            },
            .graphics => try self.cmdMan.recordGraphicsPass(&self.renderImage, &self.pipelineMan.graphics, .graphics),
            .mesh => try self.cmdMan.recordGraphicsPass(&self.renderImage, &self.pipelineMan.mesh, .mesh),
        }
        try self.cmdMan.blitToTargets(&self.renderImage, recordIds, &self.swapchainMan.swapchains);
    }

    fn queueSubmit(self: *Renderer, cmd: c.VkCommandBuffer, submitIds: []const u8, frameInFlight: u8) !void {
        var waitInfos = try self.arenaAlloc.alloc(c.VkSemaphoreSubmitInfo, submitIds.len);

        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);

            waitInfos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = swapchain.imgRdySems[frameInFlight],
                .stageMask = c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            };
        }

        var signalInfos = try self.arenaAlloc.alloc(c.VkSemaphoreSubmitInfo, submitIds.len + 1); // (+1 is Timeline Semaphore)

        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);

            signalInfos[i] = .{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
                .semaphore = swapchain.renderDoneSems[swapchain.curIndex],
                .stageMask = c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
            };
        }

        // Adding the timeline
        signalInfos[submitIds.len] = .{
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

    fn present(self: *Renderer, presentIds: []const u8) !void {
        var swapchainHandles = try self.alloc.alloc(c.VkSwapchainKHR, presentIds.len);
        defer self.alloc.free(swapchainHandles);
        var imageIndices = try self.alloc.alloc(u32, presentIds.len);
        defer self.alloc.free(imageIndices);
        var presentWaitSems = try self.alloc.alloc(c.VkSemaphore, presentIds.len);
        defer self.alloc.free(presentWaitSems);

        for (presentIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);

            swapchainHandles[i] = swapchain.handle;
            imageIndices[i] = swapchain.curIndex;
            presentWaitSems[i] = swapchain.renderDoneSems[swapchain.curIndex];
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

    fn updateDescriptors(self: *Renderer) !void {
        try self.scheduler.waitForGPU();
        self.descriptorMan.updateAllDescriptorSets(self.renderImage.view);
        self.descriptorsUpToDate = true;
    }
};
