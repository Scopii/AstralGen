const std = @import("std");
const c = @import("../c.zig");
const config = @import("../config.zig");
const Context = @import("Context.zig").Context;
const Camera = @import("../core/Camera.zig").Camera;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Window = @import("../platform/Window.zig").Window;
const CmdManager = @import("CmdManager.zig").CmdManager;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const Swapchain = @import("SwapchainManager.zig").Swapchain;
const PushConstants = @import("ShaderManager.zig").PushConstants;
const GpuImage = @import("ResourceManager.zig").GpuImage;
const GpuBuffer = @import("ResourceManager.zig").GpuBuffer;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const Object = @import("../ecs/EntityManager.zig").Object;
const check = @import("error.zig").check;
const createInstance = @import("Context.zig").createInstance;

const Allocator = std.mem.Allocator;
const RENDER_IMG_MAX = config.RENDER_IMG_MAX;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    shaderMan: ShaderManager,
    swapchainMan: SwapchainManager,
    cmdMan: CmdManager,
    scheduler: Scheduler,
    renderImages: [RENDER_IMG_MAX]?GpuImage,
    gpuObjects: GpuBuffer = undefined,
    objectCount: u32,

    pub fn init(memoryMan: *MemoryManager, objects: []Object) !Renderer {
        const alloc = memoryMan.getAllocator();
        const instance = try createInstance(alloc);
        const context = try Context.init(alloc, instance);
        var resourceMan = try ResourceManager.init(alloc, &context);
        const cmdMan = try CmdManager.init(alloc, &context, config.MAX_IN_FLIGHT);
        const scheduler = try Scheduler.init(&context, config.MAX_IN_FLIGHT);
        const shaderMan = try ShaderManager.init(alloc, &context, &resourceMan);
        const swapchainMan = try SwapchainManager.init(alloc, &context);

        var renderImages: [RENDER_IMG_MAX]?GpuImage = undefined;
        for (0..renderImages.len) |i| renderImages[i] = null;

        for (config.renderSeq) |shaderLayout| {
            const renderImg = shaderLayout.renderImg;

            if (renderImg.id > RENDER_IMG_MAX - 1) {
                std.debug.print("Renderer: RenderId Image ID cant be bigger than Max Windows\n", .{});
                return error.RenderImageIdOutOfBounds;
            }

            if (renderImages[renderImg.id] == null) {
                const gpuImg = try resourceMan.createGpuImage(renderImg.extent, renderImg.imgFormat, renderImg.memUsage);
                renderImages[renderImg.id] = gpuImg;
                std.debug.print("Renderer: RenderImage {} created\n", .{renderImg.id});
                try resourceMan.updateImageDescriptor(gpuImg.view, renderImg.id);
            }
        }

        const gpuObjects = try resourceMan.createGpuBuffer(objects);
        try resourceMan.updateObjectBufferDescriptor(gpuObjects);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resourceMan = resourceMan,
            .shaderMan = shaderMan,
            .cmdMan = cmdMan,
            .scheduler = scheduler,
            .renderImages = renderImages,
            .swapchainMan = swapchainMan,
            .gpuObjects = gpuObjects,
            .objectCount = @intCast(objects.len),
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        for (self.renderImages) |renderImg| if (renderImg != null) self.resourceMan.destroyGpuImage(renderImg.?);
        self.scheduler.deinit();
        self.cmdMan.deinit();
        self.swapchainMan.deinit();
        self.shaderMan.deinit();
        self.resourceMan.destroyGpuBuffer(self.gpuObjects);
        self.resourceMan.deinit();
        self.context.deinit();
    }

    pub fn updateWindowState(self: *Renderer, winPtrs: []*Window) !void {
        // Handle window state changes...
        for (winPtrs) |winPtr| {
            if (winPtr.state == .needDelete or winPtr.state == .needUpdate) {
                _ = c.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        var dirtyRenderIds: [config.MAX_WINDOWS]bool = .{false} ** config.MAX_WINDOWS;

        for (winPtrs) |winPtr| {
            switch (winPtr.state) {
                .needUpdate, .needCreation => {
                    try self.swapchainMan.createSwapchain(&self.context, .{ .window = winPtr });
                    dirtyRenderIds[winPtr.renderId] = true;
                },
                .needActive, .needInactive => {
                    self.swapchainMan.changeState(winPtr.windowId, if (winPtr.state == .needActive) .active else .inactive);
                },
                .needDelete => self.swapchainMan.removeSwapchain(&.{winPtr}),
                else => std.debug.print("Window State {s} cant be handled in Renderer\n", .{@tagName(winPtr.state)}),
            }
        }

        if (config.RENDER_IMG_AUTO_RESIZE == true) {
            for (0..dirtyRenderIds.len) |i| {
                if (dirtyRenderIds[i] == true and self.renderImages[i] != null) {
                    try self.updateRenderImage(@intCast(i));
                }
            }
        }
    }

    pub fn updateRenderImage(self: *Renderer, renderId: u8) !void {
        const renderImg = self.renderImages[renderId].?;

        const new = self.swapchainMan.getMaxRenderExtent(renderId);
        const old = renderImg.extent3d;

        if (new.height != 0 or new.width != 0) {
            if (new.width != old.width or new.height != old.height) {
                self.resourceMan.destroyGpuImage(renderImg);

                const newExtent = c.VkExtent3D{ .width = new.width, .height = new.height, .depth = 1 };
                self.renderImages[renderId] = try self.resourceMan.createGpuImage(newExtent, config.RENDER_IMG_FORMAT, c.VMA_MEMORY_USAGE_GPU_ONLY);

                try self.resourceMan.updateImageDescriptor(self.renderImages[renderId].?.view, renderId);
                std.debug.print("RenderImage recreated {}x{} to {}x{}\n", .{ old.width, old.height, new.width, new.height });
            }
        }
    }

    pub fn updateShaderLayout(self: *Renderer, index: usize) !void {
        _ = c.vkDeviceWaitIdle(self.context.gpi);
        try self.shaderMan.updateShaderLayout(index);
    }

    pub fn draw(self: *Renderer, cam: *Camera, runtimeAsFloat: f32) !void {
        try self.scheduler.waitForGPU();

        const frameInFlight = self.scheduler.frameInFlight;
        if (try self.swapchainMan.updateTargets(frameInFlight, &self.context) == false) return;

        const cmd = try self.cmdMan.beginRecording(frameInFlight);
        try self.recordPasses(cmd, cam, runtimeAsFloat);
        try CmdManager.recordSwapchainBlits(cmd, &self.renderImages, self.swapchainMan.targets.slice(), &self.swapchainMan.swapchains);
        try CmdManager.endRecording(cmd);

        const targets = self.swapchainMan.targets.slice();
        try self.queueSubmit(cmd, targets, frameInFlight);
        try self.swapchainMan.present(targets, self.context.presentQ);

        self.scheduler.nextFrame();
    }

    fn recordPasses(self: *Renderer, cmd: c.VkCommandBuffer, cam: *Camera, runtimeAsFloat: f32) !void {
        for (0..config.renderSeq.len) |i| {
            const renderImgId = config.renderSeq[i].renderImg.id;

            const pushConstants = PushConstants{
                .camPosAndFov = cam.getPosAndFov(),
                .camDir = cam.getForward(),
                .runtime = runtimeAsFloat,
                .dataCount = self.objectCount,
                .renderImgIndex = renderImgId,
                .viewProj = cam.getViewProj(),
            };

            try CmdManager.recordPass(
                cmd,
                &self.renderImages[renderImgId].?,
                self.shaderMan.shaderObjects[i].items,
                self.shaderMan.getRenderType(i),
                self.shaderMan.pipeLayout,
                self.resourceMan.imgDescBuffer.gpuAddress,
                pushConstants,
                config.renderSeq[i].clear,
            );
        }
    }

    fn queueSubmit(self: *Renderer, cmd: c.VkCommandBuffer, submitIds: []const u32, frameInFlight: u8) !void {
        var waitInfos: [config.MAX_WINDOWS]c.VkSemaphoreSubmitInfo = undefined;
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[frameInFlight], c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0);
        }

        var signalInfos: [config.MAX_WINDOWS + 1]c.VkSemaphoreSubmitInfo = undefined;
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderDoneSems[swapchain.curIndex], c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, 0);
        }
        // Signal CPU Timeline
        signalInfos[submitIds.len] = createSemaphoreSubmitInfo(self.scheduler.cpuSyncTimeline, c.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, self.scheduler.totalFrames + 1);

        const cmdSubmitInf = c.VkCommandBufferSubmitInfo{ .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = cmd };
        const submitInf = c.VkSubmitInfo2{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(submitIds.len),
            .pWaitSemaphoreInfos = &waitInfos,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdSubmitInf,
            .signalSemaphoreInfoCount = @intCast(submitIds.len + 1), // Swapchains + 1 Timeline
            .pSignalSemaphoreInfos = &signalInfos,
        };
        try check(c.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInf, null), "Failed main submission");
    }
};

fn createSemaphoreSubmitInfo(semaphore: c.VkSemaphore, stageMask: u64, value: u64) c.VkSemaphoreSubmitInfo {
    return .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = stageMask, .value = value };
}
