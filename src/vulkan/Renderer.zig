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
const ComputePushConstants = @import("PipelineBucket.zig").ComputePushConstants;
const GpuBuffer = @import("ResourceManager.zig").GpuBuffer;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const GpuImage = @import("ResourceManager.zig").GpuImage;
const Window = @import("../platform/Window.zig").Window;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const config = @import("../config.zig");
const Camera = @import("../core/Camera.zig").Camera;

const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resourceMan2: ResourceManager,
    pipelineMan: PipelineManager,
    swapchainMan: SwapchainManager,
    cmdMan: CmdManager,
    scheduler: Scheduler,
    renderImage: GpuImage,
    startTime: i128 = 0,
    testBuffer: GpuBuffer = undefined,

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const instance = try createInstance(alloc, config.DEBUG_MODE);
        const context = try Context.init(alloc, instance);
        const resourceMan2 = try ResourceManager.init(alloc, &context);
        const cmdMan = try CmdManager.init(alloc, &context, config.MAX_IN_FLIGHT);
        const scheduler = try Scheduler.init(&context, config.MAX_IN_FLIGHT);
        const pipelineMan = try PipelineManager.init(alloc, &context, &resourceMan2);
        const swapchainMan = try SwapchainManager.init(alloc, &context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resourceMan2 = resourceMan2,
            .pipelineMan = pipelineMan,
            .cmdMan = cmdMan,
            .scheduler = scheduler,
            .renderImage = try resourceMan2.createGpuImage(config.RENDER_IMAGE_PRESET, config.RENDER_IMAGE_FORMAT, c.VMA_MEMORY_USAGE_GPU_ONLY),
            .swapchainMan = swapchainMan,
            .startTime = std.time.nanoTimestamp(),
            .testBuffer = try resourceMan2.createTestDataBuffer(config.RENDER_IMAGE_PRESET),
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        self.resourceMan2.destroyImage(self.renderImage);
        self.scheduler.deinit();
        self.cmdMan.deinit();
        self.swapchainMan.deinit();
        self.pipelineMan.deinit();
        self.resourceMan2.destroyGpuBuffer(self.testBuffer);
        self.resourceMan2.deinit();
        self.context.deinit();
    }

    pub fn update(self: *Renderer, windows: []*Window) !void {
        // Handle window state changes...
        for (windows) |windowPtr| {
            if (windowPtr.status == .needDelete or windowPtr.status == .needUpdate) {
                _ = c.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }

        for (windows) |windowPtr| {
            switch (windowPtr.status) {
                .needUpdate => {
                    try self.swapchainMan.createSwapchain(&self.context, .{ .window = windowPtr });
                    windowPtr.status = .active;
                },
                .needActive => {
                    try self.swapchainMan.addActive(windowPtr);
                    windowPtr.status = .active;
                },
                .needInactive => {
                    self.swapchainMan.removeActive(windowPtr);
                    windowPtr.status = .inactive;
                },
                .needCreation => {
                    try self.swapchainMan.createSwapchain(&self.context, .{ .window = windowPtr });
                    windowPtr.status = .active;
                },
                .needDelete => self.swapchainMan.removeSwapchain(&.{windowPtr}),
                else => std.debug.print("Window State {s} cant be handled in Renderer\n", .{@tagName(windowPtr.status)}),
            }
        }
        self.swapchainMan.updateMaxExtent();
        const extent = self.swapchainMan.getMaxExtent();

        if (extent.height != 0 or extent.width != 0) {
            if (extent.width != self.renderImage.extent3d.width or extent.height != self.renderImage.extent3d.height) {
                self.resourceMan2.destroyImage(self.renderImage);
                const newRenderExtent = c.VkExtent3D{ .width = extent.width, .height = extent.height, .depth = config.RENDER_IMAGE_PRESET.depth };
                self.renderImage = try self.resourceMan2.createGpuImage(newRenderExtent, c.VK_FORMAT_R16G16B16A16_SFLOAT, c.VMA_MEMORY_USAGE_GPU_ONLY);
                try self.resourceMan2.updateImageDescriptor(self.renderImage.view, 0);
                std.debug.print("Render Image now {}x{}\n", .{ extent.width, extent.height });
            }
        }
    }

    pub fn updatePipeline(self: *Renderer, pipeType: PipelineType) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.pipelineMan.updatePipeline(pipeType);
    }

    pub fn draw(self: *Renderer, cam: *Camera, runtimeAsFloat: f32) !void {
        try self.scheduler.waitForGPU();

        const frameInFlight = self.scheduler.frameInFlight;
        if (try self.swapchainMan.updateTargets(frameInFlight, &self.context) == false) return;

        self.cmdMan.needUpdate = true; // Hard Coded Cmd Recording Updates

        try self.cmdMan.beginRecording(frameInFlight);
        try self.recordCommands(cam, runtimeAsFloat);
        const cmd = try self.cmdMan.endRecording();

        const targets = self.swapchainMan.targets.slice();
        try self.queueSubmit(cmd, targets, frameInFlight);
        try self.present(targets);

        self.scheduler.nextFrame();
    }

    fn recordCommands(self: *Renderer, cam: *Camera, runtimeAsFloat: f32) !void {
        const activeGroups = self.swapchainMan.activeGroups;

        for (0..activeGroups.len) |i| {
            if (activeGroups[i].len != 0) {
                const pipeType: PipelineType = @enumFromInt(i);

                const compPushConstants = ComputePushConstants{
                    .camPosAndFov = cam.getPosAndFov(),
                    .camDir = cam.getForward(),
                    .dataAddress = self.testBuffer.gpuAddress,
                    .runtime = runtimeAsFloat,
                    .dataCount = @intCast(self.testBuffer.size / @sizeOf([4]f32)),
                };

                switch (pipeType) {
                    .compute => try self.cmdMan.recordComputePass(&self.renderImage, &self.pipelineMan.pipelines[0], self.resourceMan2.imageBuffer.gpuAddress, compPushConstants),
                    .graphics => try self.cmdMan.recordGraphicsPass(&self.renderImage, &self.pipelineMan.pipelines[1], .graphics),
                    .mesh => try self.cmdMan.recordGraphicsPass(&self.renderImage, &self.pipelineMan.pipelines[2], .mesh),
                }
                try self.cmdMan.blitToTargets(&self.renderImage, activeGroups[i].slice(), &self.swapchainMan.swapchains);
            }
        }
    }

    fn queueSubmit(self: *Renderer, cmd: c.VkCommandBuffer, submitIds: []const u8, frameInFlight: u8) !void {
        var waitInfos = try self.arenaAlloc.alloc(c.VkSemaphoreSubmitInfo, submitIds.len);
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[frameInFlight], c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0);
        }

        var signalInfos = try self.arenaAlloc.alloc(c.VkSemaphoreSubmitInfo, submitIds.len + 1); // (+1 is Timeline Semaphore)
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderDoneSems[swapchain.curIndex], c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, 0);
        }
        // Adding the timeline
        signalInfos[submitIds.len] =
            createSemaphoreSubmitInfo(self.scheduler.cpuSyncTimeline, c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, self.scheduler.totalFrames + 1);

        const cmdSubmitInfo = createCmdSubmitInfo(cmd);
        const submitInf = createSubmitInfo(waitInfos, &cmdSubmitInfo, signalInfos);
        try check(c.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInf, null), "Failed main submission");
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
        const presentInf = createPresentInfo(presentWaitSems, swapchainHandles, imageIndices);

        const result = c.vkQueuePresentKHR(self.context.presentQ, &presentInf);
        if (result != c.VK_SUCCESS and result != c.VK_ERROR_OUT_OF_DATE_KHR and result != c.VK_SUBOPTIMAL_KHR) {
            try check(result, "Failed to present swapchain image");
        }
    }
};

fn createSemaphoreSubmitInfo(semaphore: c.VkSemaphore, stageMask: u64, value: u64) c.VkSemaphoreSubmitInfo {
    return .{
        .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,
        .semaphore = semaphore,
        .stageMask = stageMask,
        .value = value,
    };
}

fn createSubmitInfo(waitInfos: []c.VkSemaphoreSubmitInfo, cmdInfo: *const c.VkCommandBufferSubmitInfo, signalInfos: []c.VkSemaphoreSubmitInfo) c.VkSubmitInfo2 {
    return c.VkSubmitInfo2{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
        .waitSemaphoreInfoCount = @intCast(waitInfos.len),
        .pWaitSemaphoreInfos = waitInfos.ptr,
        .commandBufferInfoCount = 1,
        .pCommandBufferInfos = cmdInfo,
        .signalSemaphoreInfoCount = @intCast(signalInfos.len),
        .pSignalSemaphoreInfos = signalInfos.ptr,
    };
}

fn createCmdSubmitInfo(cmd: c.VkCommandBuffer) c.VkCommandBufferSubmitInfo {
    return .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO,
        .commandBuffer = cmd,
    };
}

fn createPresentInfo(waitSemaphores: []c.VkSemaphore, swapchainHandles: []c.VkSwapchainKHR, imageIndices: []u32) c.VkPresentInfoKHR {
    return c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = @intCast(waitSemaphores.len),
        .pWaitSemaphores = waitSemaphores.ptr,
        .swapchainCount = @intCast(swapchainHandles.len),
        .pSwapchains = swapchainHandles.ptr,
        .pImageIndices = imageIndices.ptr,
    };
}
