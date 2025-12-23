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
const Resource = @import("resources/ResourceManager.zig").Resource;

const Allocator = std.mem.Allocator;
const rc = @import("../configs/renderConfig.zig");

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    shaderMan: ShaderManager,
    swapchainMan: SwapchainManager,
    cmdMan: CmdManager,
    scheduler: Scheduler,
    passes: std.array_list.Managed(rc.Pass),

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const instance = try createInstance(alloc);
        const context = try Context.init(alloc, instance);
        const resourceMan = try ResourceManager.init(alloc, &context);
        const cmdMan = try CmdManager.init(alloc, &context, rc.MAX_IN_FLIGHT, &resourceMan);
        const scheduler = try Scheduler.init(&context, rc.MAX_IN_FLIGHT);
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
            .passes = std.array_list.Managed(rc.Pass).init(alloc),
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
        var dirtyPassImgIds: [rc.MAX_WINDOWS]?u32 = .{null} ** rc.MAX_WINDOWS;

        for (0..winPtrs.len) |i| {
            const winPtr = winPtrs[i];

            switch (winPtr.state) {
                .needUpdate, .needCreation => {
                    try self.swapchainMan.createSwapchain(&self.context, .{ .window = winPtr });
                    dirtyPassImgIds[i] = winPtr.passImgId;
                },
                .needActive, .needInactive => {
                    self.swapchainMan.changeState(winPtr.windowId, if (winPtr.state == .needActive) .active else .inactive);
                },
                .needDelete => self.swapchainMan.removeSwapchain(&.{winPtr}),
                else => std.debug.print("Window State {s} cant be handled in Renderer\n", .{@tagName(winPtr.state)}),
            }
        }

        if (rc.RENDER_IMG_AUTO_RESIZE == true) {
            for (0..dirtyPassImgIds.len) |i| {
                if (dirtyPassImgIds[i] == null) break;

                const gpuId = dirtyPassImgIds[i].?;
                const resource = try self.resourceMan.getResourcePtr(gpuId);
                switch (resource.resourceType) {
                    .gpuImg => |passImg| try self.updatePassImage(gpuId, passImg),
                    else => std.debug.print("Warning: updateRenderImage failed, renderID: {} is not an Image", .{gpuId}),
                }
            }
        }
    }

    pub fn updatePassImage(self: *Renderer, gpuId: u32, img: Resource.GpuImage) !void {
        const old = img.extent3d;
        const new = self.swapchainMan.getMaxRenderExtent(gpuId);

        if (new.height != 0 or new.width != 0) {
            if (new.width != old.width or new.height != old.height) {
                const extent = vk.VkExtent3D{ .width = new.width, .height = new.height, .depth = 1 };
                const newImg = rc.ResourceInfo{
                    .gpuId = gpuId,
                    .binding = rc.RENDER_IMG_BINDING,
                    .memUsage = .GpuOptimal,
                    .info = .{ .imgInf = .{ .extent = extent, .arrayIndex = img.arrayIndex } },
                };
                self.resourceMan.destroyResource(gpuId);
                try self.resourceMan.createResource(newImg);
                std.debug.print("Render Image ID {} recreated {}x{} to {}x{}\n", .{ gpuId, old.width, old.height, new.width, new.height });
            }
        }
    }

    pub fn addPasses(self: *Renderer, passes: []const rc.Pass) !void {
        for (passes) |passInf| {
            const shaderArray = self.shaderMan.getShaders(passInf.shaderIds);
            const validShaders = shaderArray[0..passInf.shaderIds.len];

            const passType = checkShaderLayout(validShaders) catch |err| {
                std.debug.print("Pass {} Shader Layout invalid", .{err});
                return error.PassInvalid;
            };
            try self.passes.append(.{ .passType = passType, .passImgId = passInf.passImgId, .shaderIds = passInf.shaderIds, .clear = passInf.clear });
        }
    }

    pub fn createResource(self: *Renderer, resourceInf: rc.ResourceInfo) !void {
        try self.resourceMan.createResource(resourceInf);
    }

    pub fn updateResource(self: *Renderer, resourceInf: rc.ResourceInfo, data: anytype) !void {
        try self.resourceMan.updateResource(resourceInf, data);
    }

    pub fn draw(self: *Renderer, cam: *Camera, runtimeAsFloat: f32) !void {
        try self.scheduler.waitForGPU();

        const frameInFlight = self.scheduler.frameInFlight;
        if (try self.swapchainMan.updateTargets(frameInFlight, &self.context) == false) return;

        const cmd = try self.cmdMan.beginRecording(frameInFlight);
        try self.recordPasses(cmd, cam, runtimeAsFloat);

        try CmdManager.recordSwapchainBlits(cmd, &self.resourceMan, self.swapchainMan.targets.slice(), &self.swapchainMan.swapchains);
        try CmdManager.endRecording(cmd);

        const targets = self.swapchainMan.targets.slice();
        try self.queueSubmit(cmd, targets, frameInFlight);
        try self.swapchainMan.present(targets, self.context.presentQ);

        self.scheduler.nextFrame();
    }

    fn recordPasses(self: *Renderer, cmd: vk.VkCommandBuffer, cam: *Camera, runtimeAsFloat: f32) !void {
        for (self.passes.items) |pass| {
            const gpuResource = try self.resourceMan.getResourcePtr(1); // HARD CODED CURRENTLY

            const gpuBufferCount: u32 = switch (gpuResource.resourceType) {
                .gpuBuf => |buf| buf.count,
                else => return error.ObjectBufferIsNotGpuBuffer,
            };
            const passImg = try self.resourceMan.getValidatedGpuResourcePtr(pass.passImgId, .gpuImg);

            const pushConstants = PushConstants{
                .camPosAndFov = cam.getPosAndFov(),
                .camDir = cam.getForward(),
                .runtime = runtimeAsFloat,
                .dataCount = gpuBufferCount,
                .passImgIndex = passImg.arrayIndex,
                .viewProj = cam.getViewProj(),
            };
            const shaderArray = self.shaderMan.getShaders(pass.shaderIds);
            const validShaders = shaderArray[0..pass.shaderIds.len];
            try self.cmdMan.recordPass(cmd, passImg, validShaders, pass.passType, pushConstants, pass.clear);
        }
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders);
    }

    fn queueSubmit(self: *Renderer, cmd: vk.VkCommandBuffer, submitIds: []const u32, frameInFlight: u8) !void {
        var waitInfos: [rc.MAX_WINDOWS]vk.VkSemaphoreSubmitInfo = undefined;
        for (submitIds, 0..) |id, i| {
            const swapchain = self.swapchainMan.swapchains.getAtIndex(id);
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[frameInFlight], vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT, 0);
        }

        var signalInfos: [rc.MAX_WINDOWS + 1]vk.VkSemaphoreSubmitInfo = undefined;
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

fn checkShaderLayout(shaders: []const ShaderObject) !rc.Pass.PassType {
    var shdr: [9]u8 = .{0} ** 9;
    var prevIndex: i8 = -1;

    for (shaders) |shader| {
        const curIndex: i8 = switch (shader.stage) {
            .compute => 0,
            .vert => 1,
            .tessControl => 2,
            .tessEval => 3,
            .geometry => 4,
            .task => 5,
            .mesh => 6,
            .meshNoTask => 6, // LAYOUT NOT CHECKED YET
            .frag => 7,
        };
        if (curIndex < prevIndex) return error.ShaderLayoutOrderInvalid;
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
