const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Camera = @import("../core/Camera.zig").Camera;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Window = @import("../platform/Window.zig").Window;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const CmdManager = @import("CmdManager.zig").CmdManager;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const PushConstants = @import("resources/DescriptorManager.zig").PushConstants;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const Object = @import("../ecs/EntityManager.zig").Object;
const check = @import("ErrorHelpers.zig").check;
const createInstance = @import("Context.zig").createInstance;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;

const Allocator = std.mem.Allocator;
const renderCon = @import("../configs/renderConfig.zig");
const RENDER_IMG_MAX = renderCon.GPU_IMG_MAX;

const Pass = struct {
    renderType: renderCon.RenderType,
    renderImgInf: renderCon.GpuImageInfo,
    shaderIds: []const u8,
    clear: bool,
};

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    shaderMan: ShaderManager,
    swapchainMan: SwapchainManager,
    cmdMan: CmdManager,
    scheduler: Scheduler,
    passes: std.array_list.Managed(Pass),

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const instance = try createInstance(alloc);
        const context = try Context.init(alloc, instance);
        var resourceMan = try ResourceManager.init(alloc, &context);
        const cmdMan = try CmdManager.init(alloc, &context, renderCon.MAX_IN_FLIGHT);
        const scheduler = try Scheduler.init(&context, renderCon.MAX_IN_FLIGHT);
        const shaderMan = try ShaderManager.init(alloc, &context, &resourceMan);
        const swapchainMan = try SwapchainManager.init(alloc, &context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resourceMan = resourceMan,
            .shaderMan = shaderMan,
            .cmdMan = cmdMan,
            .scheduler = scheduler,
            .swapchainMan = swapchainMan,
            .passes = std.array_list.Managed(Pass).init(alloc),
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = vk.vkDeviceWaitIdle(self.context.gpi);
        self.scheduler.deinit();
        self.cmdMan.deinit();
        self.swapchainMan.deinit();
        self.shaderMan.deinit();
        self.resourceMan.deinit();
        self.context.deinit();
        self.passes.deinit();
    }

    pub fn updateWindowState(self: *Renderer, winPtrs: []*Window) !void {
        // Handle window state changes...
        for (winPtrs) |winPtr| {
            if (winPtr.state == .needDelete or winPtr.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        var dirtyRenderIds: [renderCon.MAX_WINDOWS]bool = .{false} ** renderCon.MAX_WINDOWS;

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

        if (renderCon.RENDER_IMG_AUTO_RESIZE == true) {
            for (0..dirtyRenderIds.len) |i| {
                if (dirtyRenderIds[i] == true and self.resourceMan.isGpuImageIdUsed(@intCast(i)) != false) {
                    try self.updateRenderImage(@intCast(i));
                }
            }
        }
    }

    pub fn updateRenderImage(self: *Renderer, renderId: u8) !void {
        const new = self.swapchainMan.getMaxRenderExtent(renderId);
        const gpuImg = try self.resourceMan.getGpuImage(renderId);
        const old = gpuImg.extent3d;

        if (new.height != 0 or new.width != 0) {
            if (new.width != old.width or new.height != old.height) {
                self.resourceMan.destroyGpuImage(renderId);

                const newExtent = vk.VkExtent3D{ .width = new.width, .height = new.height, .depth = 1 };
                try self.resourceMan.createGpuImage(renderId, newExtent, renderCon.RENDER_IMG_FORMAT, vk.VMA_MEMORY_USAGE_GPU_ONLY);
                std.debug.print("RenderImage recreated {}x{} to {}x{}\n", .{ old.width, old.height, new.width, new.height });
            }
        }
    }

    pub fn addPasses(self: *Renderer, passConfigs: []const renderCon.passInfo) !void {
        for (passConfigs) |passConfig| {
            const shaderArray = self.shaderMan.getShaders(passConfig.shaderIds);
            const validShaders = shaderArray[0..passConfig.shaderIds.len];

            const renderType = checkShaderLayout(validShaders) catch |err| {
                std.debug.print("Pass {} Shader Layout invalid", .{err});
                return error.PassInvalid;
            };
            try self.createRenderImage(passConfig.renderImg);
            try self.passes.append(.{ .renderType = renderType, .renderImgInf = passConfig.renderImg, .shaderIds = passConfig.shaderIds, .clear = passConfig.clear });
        }
    }

    pub fn createGpuBuffers(self: *Renderer, comptime gpuBufConfigs: []const renderCon.GpuBufferInfo) !void {
        try self.resourceMan.createGpuBuffer(gpuBufConfigs);
    }

    pub fn updateGpuBuffer(self: *Renderer, buffId: u8, objects: []Object) !void { // SHOULD LATER TAKE CONFIG
        try self.resourceMan.updateGpuBuffer(buffId, objects);
    }

    pub fn createRenderImage(self: *Renderer, renderRes: renderCon.GpuImageInfo) !void {
        if (renderRes.id > RENDER_IMG_MAX - 1) {
            std.debug.print("Renderer: RenderId Image ID cant be bigger than Max Windows\n", .{});
            return error.RenderImageIdOutOfBounds;
        }

        const imgUsed = self.resourceMan.isGpuImageIdUsed(renderRes.id);

        if (imgUsed == false) {
            try self.resourceMan.createGpuImage(renderRes.id, renderRes.extent, renderRes.imgFormat, renderRes.memUsage);
            std.debug.print("Renderer: RenderImage {} created\n", .{renderRes.id});
        }
    }

    pub fn updateShaderLayout(self: *Renderer, index: usize) !void {
        _ = vk.vkDeviceWaitIdle(self.context.gpi);
        try self.shaderMan.updateShaderLayout(index);
    }

    pub fn draw(self: *Renderer, cam: *Camera, runtimeAsFloat: f32) !void {
        try self.scheduler.waitForGPU();

        const frameInFlight = self.scheduler.frameInFlight;
        if (try self.swapchainMan.updateTargets(frameInFlight, &self.context) == false) return;

        const cmd = try self.cmdMan.beginRecording(frameInFlight);
        try self.recordPasses(cmd, cam, runtimeAsFloat);

        const imgMap = self.resourceMan.getGpuImageMapPtr();
        try CmdManager.recordSwapchainBlits(cmd, imgMap, self.swapchainMan.targets.slice(), &self.swapchainMan.swapchains);
        try CmdManager.endRecording(cmd);

        const targets = self.swapchainMan.targets.slice();
        try self.queueSubmit(cmd, targets, frameInFlight);
        try self.swapchainMan.present(targets, self.context.presentQ);

        self.scheduler.nextFrame();
    }

    fn recordPasses(self: *Renderer, cmd: vk.VkCommandBuffer, cam: *Camera, runtimeAsFloat: f32) !void {
        for (self.passes.items) |pass| {
            const renderImgId = pass.renderImgInf.id;

            const gpuBuffer = try self.resourceMan.getGpuBuffer(0);

            const pushConstants = PushConstants{
                .camPosAndFov = cam.getPosAndFov(),
                .camDir = cam.getForward(),
                .runtime = runtimeAsFloat,
                .dataCount = gpuBuffer.count,
                .renderImgIndex = renderImgId,
                .viewProj = cam.getViewProj(),
            };

            const shaderArray = self.shaderMan.getShaders(pass.shaderIds);
            const validShaders = shaderArray[0..pass.shaderIds.len];

            try CmdManager.recordPass(
                cmd,
                self.resourceMan.getGpuImagePtr(renderImgId),
                validShaders,
                pass.renderType,
                self.resourceMan.descMan.pipeLayout,
                self.resourceMan.descMan.descBuffer.gpuAddress,
                pushConstants,
                pass.clear,
            );
        }
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []LoadedShader) !void {
        try self.shaderMan.createShaders(loadedShaders);
    }

    fn queueSubmit(self: *Renderer, cmd: vk.VkCommandBuffer, submitIds: []const u32, frameInFlight: u8) !void {
        var waitInfos: [renderCon.MAX_WINDOWS]vk.VkSemaphoreSubmitInfo = undefined;
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[frameInFlight], vk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0);
        }

        var signalInfos: [renderCon.MAX_WINDOWS + 1]vk.VkSemaphoreSubmitInfo = undefined;
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderDoneSems[swapchain.curIndex], vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, 0);
        }
        // Signal CPU Timeline
        signalInfos[submitIds.len] = createSemaphoreSubmitInfo(self.scheduler.cpuSyncTimeline, vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, self.scheduler.totalFrames + 1);

        const cmdSubmitInf = vk.VkCommandBufferSubmitInfo{ .sType = vk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO, .commandBuffer = cmd };
        const submitInf = vk.VkSubmitInfo2{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(submitIds.len),
            .pWaitSemaphoreInfos = &waitInfos,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdSubmitInf,
            .signalSemaphoreInfoCount = @intCast(submitIds.len + 1), // Swapchains + 1 Timeline
            .pSignalSemaphoreInfos = &signalInfos,
        };
        try check(vk.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInf, null), "Failed main submission");
    }
};

fn createSemaphoreSubmitInfo(semaphore: vk.VkSemaphore, stageMask: u64, value: u64) vk.VkSemaphoreSubmitInfo {
    return .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = stageMask, .value = value };
}

fn checkShaderLayout(shaders: []const ShaderObject) !renderCon.RenderType {
    var shdr: [9]u8 = .{0} ** 9;
    var prevIndex: i8 = -1;

    for (shaders) |shader| {
        const curIndex: i8 = switch (shader.stage) {
            .compute => 0,
            .vertex => 1,
            .tessControl => 2,
            .tessEval => 3,
            .geometry => 4,
            .task => 5,
            .mesh => 6,
            //.meshNoTask => 6, // LAYOUT NOT CHECKED YET
            .frag => 7,
        };
        if (curIndex < prevIndex) return error.ShaderLayoutOrderInvalid; // IS WRONG? <= -> < ???
        prevIndex = curIndex;
        shdr[@intCast(curIndex)] += 1;
    }
    switch (shaders.len) {
        1 => if (shdr[0] == 1) return .computePass else if (shdr[1] == 1) return .vertexPass,
        2 => if (shdr[6] == 1 and shdr[7] == 1) return .meshPass,
        3 => if (shdr[5] == 1 and shdr[6] == 1 and shdr[7] == 1) return .taskMeshPass,
        else => {},
    }
    if (shdr[1] == 1 and shdr[2] <= 1 and shdr[3] <= 1 and shdr[4] <= 1 and shdr[5] == 0 and shdr[6] == 0 and shdr[7] == 1) return .graphicsPass;
    if (shdr[2] != shdr[3]) return error.ShaderLayoutTessellationMismatch;
    return error.ShaderLayoutInvalid;
}
