const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Window = @import("../platform/Window.zig").Window;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const CmdManager = @import("CmdManager.zig").CmdManager;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const PushConstants = @import("resources/DescriptorManager.zig").PushConstants;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const check = @import("ErrorHelpers.zig").check;
const createInstance = @import("Context.zig").createInstance;
const ShaderObject = @import("ShaderObject.zig").ShaderObject;
const Resource = @import("resources/ResourceManager.zig").Resource;
const RenderGraph = @import("RenderGraph.zig").RenderGraph;
const RendererData = @import("../App.zig").RendererData;
const rc = @import("../configs/renderConfig.zig");
const Allocator = std.mem.Allocator;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resourceMan: ResourceManager,
    renderGraph: RenderGraph,
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
        const renderGraph = try RenderGraph.init(alloc, &resourceMan);
        const cmdMan = try CmdManager.init(alloc, &context, rc.MAX_IN_FLIGHT, &resourceMan);
        const scheduler = try Scheduler.init(&context, rc.MAX_IN_FLIGHT);
        const shaderMan = try ShaderManager.init(alloc, &context, &resourceMan);
        const swapchainMan = try SwapchainManager.init(alloc, &context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resourceMan = resourceMan,
            .renderGraph = renderGraph,
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
        self.renderGraph.deinit();
        self.context.deinit();
        self.passes.deinit();
    }

    pub fn updateWindowStates(self: *Renderer, tempWindows: []const Window) !void {
        for (tempWindows) |tempWindow| {
            if (tempWindow.state == .needDelete or tempWindow.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }

        var dirtyImgIds: [rc.MAX_WINDOWS]?u32 = .{null} ** rc.MAX_WINDOWS;

        for (0..tempWindows.len) |i| {
            const tempWindow = tempWindows[i];
            switch (tempWindow.state) {
                .needUpdate, .needCreation => {
                    try self.swapchainMan.createSwapchain(&self.context, .{ .window = tempWindow });
                    dirtyImgIds[i] = tempWindow.passImgId;
                },
                .needActive, .needInactive => {
                    self.swapchainMan.changeState(tempWindow.windowId, if (tempWindow.state == .needActive) .active else .inactive);
                },
                .needDelete => self.swapchainMan.removeSwapchain(&.{tempWindow}),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(tempWindow.state)}),
            }
        }

        if (rc.RENDER_IMG_AUTO_RESIZE == true) {
            for (0..dirtyImgIds.len) |i| {
                if (dirtyImgIds[i] == null) break;

                const gpuId = dirtyImgIds[i].?;
                const resource = try self.resourceMan.getResourcePtr(gpuId);
                switch (resource.resourceType) {
                    .gpuImg => |passImg| try self.updatePassImage(gpuId, passImg),
                    else => std.debug.print("Warning: updateRenderImage failed, renderID: {} is not an Image", .{gpuId}),
                }
            }
        }
    }

    pub fn updatePassImage(self: *Renderer, gpuId: u32, img: Resource.GpuImage) !void {
        const old = img.imgInf.extent;
        const new = self.swapchainMan.getMaxRenderExtent(gpuId);

        if (new.height != 0 or new.width != 0) {
            if (new.width != old.width or new.height != old.height) {
                const newImgInf = rc.ResourceInf.ImgInf{ .extent = .{ .width = new.width, .height = new.height, .depth = 1 }, .imgType = img.imgInf.imgType };
                try self.resourceMan.replaceResource(gpuId, newImgInf);
                std.debug.print("Render Image ID {} recreated {}x{} to {}x{}\n", .{ gpuId, old.width, old.height, new.width, new.height });
            }
        }
    }

    pub fn createPass(self: *Renderer, passes: []const rc.Pass) !void {
        for (passes) |pass| {
            const shaders = self.shaderMan.getShaders(pass.shaderIds)[0..pass.shaderIds.len];

            const passType = checkShaderLayout(shaders) catch |err| {
                std.debug.print("Pass {} Shader Layout invalid", .{err});
                return error.PassInvalid;
            };
            const passKind = pass.kind;

            switch (passType) {
                .computePass => if (passKind != .compute) return error.PassInvalid,
                .graphicsPass, .vertexPass => if (passKind != .graphics) return error.PassInvalid,
                .taskMeshPass, .meshPass => if (passKind != .taskOrMesh) return error.PassInvalid,
            }
            try self.passes.append(pass);
        }
    }

    pub fn draw(self: *Renderer, rendererData: RendererData) !void {
        try self.scheduler.waitForGPU();
        const frameInFlight = self.scheduler.frameInFlight;

        if (try self.swapchainMan.updateTargets(frameInFlight, &self.context) == false) return;
        const targets = self.swapchainMan.getTargets();

        const cmd = try self.cmdMan.beginRecording(frameInFlight);

        try self.renderGraph.recordTransfers(cmd, &self.resourceMan);
        // Reset the staging offset for the next frame's potential uploads
        self.resourceMan.stagingOffset = 0;
        self.resourceMan.pendingTransfers.clearRetainingCapacity();

        try self.recordPasses(cmd, rendererData);
        try self.renderGraph.recordSwapchainBlits(cmd, targets, &self.swapchainMan.swapchains, &self.resourceMan);
        try CmdManager.endRecording(cmd);

        try self.queueSubmit(cmd, targets, frameInFlight);
        try self.swapchainMan.present(targets, self.context.presentQ);

        self.scheduler.nextFrame();
    }

    fn recordPasses(self: *Renderer, cmd: vk.VkCommandBuffer, rendererData: RendererData) !void {
        var pcs = PushConstants{ .runtime = rendererData.runtime };

        // Adjust Push Constants for every Pass
        for (self.passes.items) |pass| {
            if (pass.shaderSlots.len > pcs.resUsageInfos.len) return error.TooManyShaderSlotsInPass;
            // Assign Shader Slots
            for (0..pass.shaderSlots.len) |i| {
                const slot = pass.shaderSlots[i];
                const resource = try self.resourceMan.getResourcePtr(pass.resUsages[slot].id);
                switch (resource.resourceType) {
                    .gpuBuf => |gpuBuf| {
                        pcs.resUsageInfos[i].index = resource.bindlessIndex;
                        pcs.resUsageInfos[i].count = gpuBuf.count;
                    },
                    .gpuImg => |_| {
                        pcs.resUsageInfos[i].index = resource.bindlessIndex;
                        pcs.resUsageInfos[i].count = 1;
                    },
                }
            }
            // Assign Render Image
            if (pass.renderImgId) |imgId| {
                const resource = try self.resourceMan.getResourcePtr(imgId);
                switch (resource.resourceType) {
                    .gpuImg => pcs.renderImgIdx = resource.bindlessIndex,
                    else => return error.RenderImgIdIsNotImage,
                }
            }

            const shaders = self.shaderMan.getShaders(pass.shaderIds)[0..pass.shaderIds.len];
            try self.renderGraph.recordPassBarriers(cmd, pass, &self.resourceMan);
            try self.renderGraph.recordPass(cmd, pass, pcs, shaders, &self.resourceMan);
        }
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

    pub fn addShaders(self: *Renderer, loadedShaders: []LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders);
    }

    pub fn createResource(self: *Renderer, resourceInf: rc.ResourceInf) !void {
        try self.resourceMan.createResource(resourceInf);
    }

    pub fn updateResource(self: *Renderer, resourceInf: rc.ResourceInf, data: anytype) !void {
        try self.resourceMan.updateResource(resourceInf, data);
    }
};

fn createSemaphoreSubmitInfo(semaphore: vk.VkSemaphore, stageMask: u64, value: u64) vk.VkSemaphoreSubmitInfo {
    return .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = stageMask, .value = value };
}

fn checkShaderLayout(shaders: []const ShaderObject) !enum { computePass, graphicsPass, meshPass, taskMeshPass, vertexPass } {
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
