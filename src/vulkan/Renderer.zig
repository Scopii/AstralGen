const std = @import("std");
const vk = @import("../modules/vk.zig").c;
const Context = @import("Context.zig").Context;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Window = @import("../platform/Window.zig").Window;
const LoadedShader = @import("../core/ShaderCompiler.zig").LoadedShader;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const ResourceManager = @import("resources/ResourceManager.zig").ResourceManager;
const MemoryManager = @import("../core/MemoryManager.zig").MemoryManager;
const createInstance = @import("Context.zig").createInstance;
const RenderGraph = @import("RenderGraph.zig").RenderGraph;
const RendererData = @import("../App.zig").RendererData;
const rc = @import("../configs/renderConfig.zig");
const Allocator = std.mem.Allocator;
const Command = @import("Command.zig").Command;
const vh = @import("Helpers.zig");
const Pass = @import("Pass.zig").Pass;
const Texture = @import("resources/Texture.zig").Texture;
const Buffer = @import("resources/Buffer.zig").Buffer;

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: *Context,
    resMan: ResourceManager,
    renderGraph: RenderGraph,
    shaderMan: ShaderManager,
    swapMan: SwapchainManager,
    scheduler: Scheduler,
    passes: std.array_list.Managed(Pass),

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const context = try alloc.create(Context);
        context.* = try Context.init(alloc);
        const resMan = try ResourceManager.init(alloc, context);
        const renderGraph = try RenderGraph.init(alloc, context, &resMan);
        const scheduler = try Scheduler.init(context, rc.MAX_IN_FLIGHT);
        const shaderMan = try ShaderManager.init(alloc, context, &resMan);
        const swapMan = try SwapchainManager.init(alloc, context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resMan = resMan,
            .renderGraph = renderGraph,
            .shaderMan = shaderMan,
            .scheduler = scheduler,
            .swapMan = swapMan,
            .passes = std.array_list.Managed(Pass).init(alloc),
        };
    }

    pub fn deinit(self: *Renderer) void {
        _ = vk.vkDeviceWaitIdle(self.context.gpi);
        self.scheduler.deinit();
        self.swapMan.deinit();
        self.shaderMan.deinit();
        self.resMan.deinit();
        self.renderGraph.deinit();
        self.context.deinit();
        self.alloc.destroy(self.context);
        self.passes.deinit();
    }

    pub fn updateWindowStates(self: *Renderer, tempWindows: []const Window) !void {
        for (tempWindows) |tempWindow| {
            if (tempWindow.state == .needDelete or tempWindow.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }

        var dirtyImgIds: [rc.MAX_WINDOWS]?Texture.TexId = .{null} ** rc.MAX_WINDOWS;

        for (0..tempWindows.len) |i| {
            const tempWindow = tempWindows[i];
            switch (tempWindow.state) {
                .needUpdate, .needCreation => {
                    try self.swapMan.createSwapchain(self.context, .{ .window = tempWindow });
                    dirtyImgIds[i] = tempWindow.renderTexId;
                },
                .needActive, .needInactive => {
                    self.swapMan.changeState(tempWindow.winId, if (tempWindow.state == .needActive) true else false);
                },
                .needDelete => self.swapMan.removeSwapchain(&.{tempWindow}),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(tempWindow.state)}),
            }
        }

        if (rc.RENDER_IMG_AUTO_RESIZE == true) {
            for (0..dirtyImgIds.len) |i| {
                if (dirtyImgIds[i] == null) break;

                const texId = dirtyImgIds[i].?;
                const passImg = try self.resMan.getTexturePtr(texId);
                try self.updatePassImage(texId, passImg.*);
            }
        }
    }

    pub fn updatePassImage(self: *Renderer, texId: Texture.TexId, img: Texture) !void {
        const old = img.base.extent;
        const new = self.swapMan.getMaxRenderExtent(texId);

        if (new.height != 0 or new.width != 0) {
            if (new.width != old.width or new.height != old.height) {
                const imgInf = Texture.TexInf{
                    .id = texId,
                    .width = new.width,
                    .height = new.height,
                    .depth = 1,
                    .typ = img.base.texType,
                    .mem = .Gpu,
                };
                try self.resMan.replaceTexture(texId, imgInf);
                std.debug.print("Render Texture ID {} recreated {}x{} to {}x{}\n", .{ texId.val, old.width, old.height, new.width, new.height });
            }
        }
    }

    pub fn createPasses(self: *Renderer, passes: []const Pass) !void {
        for (passes) |pass| {
            if (self.shaderMan.isPassValid(pass) == true) {
                try self.passes.append(pass);
            } else std.debug.print("Error: Pass ShaderLayout does not match Pass Type -> not appended\n", .{});
        }
    }

    pub fn draw(self: *Renderer, rendererData: RendererData) !void {
        try self.scheduler.waitForGPU();
        const frameInFlight = self.scheduler.frameInFlight;

        if (try self.swapMan.updateTargets(frameInFlight, self.context) == false) return;
        const targets = self.swapMan.getTargets();

        const cmd = try self.renderGraph.recordFrame(frameInFlight, &self.resMan, rendererData, targets, &self.swapMan.swapchains, self.passes.items, &self.shaderMan);

        try self.queueSubmit(&cmd, targets, frameInFlight);
        try self.swapMan.present(targets, self.context.presentQ);

        self.scheduler.nextFrame();
    }

    fn queueSubmit(self: *Renderer, cmd: *const Command, targets: []const u32, frameInFlight: u8) !void {
        var waitInfos: [rc.MAX_WINDOWS]vk.VkSemaphoreSubmitInfo = undefined;
        for (targets, 0..) |id, i| {
            const swapchain = self.swapMan.swapchains.getAtIndex(id);
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[frameInFlight], vk.VK_PIPELINE_STAGE_2_TRANSFER_BIT, 0);
        }

        var signalInfos: [rc.MAX_WINDOWS + 1]vk.VkSemaphoreSubmitInfo = undefined;
        for (targets, 0..) |id, i| {
            const swapchain = self.swapMan.swapchains.getAtIndex(id);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderDoneSems[swapchain.curIndex], vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, 0);
        }
        // Signal CPU Timeline
        signalInfos[targets.len] = createSemaphoreSubmitInfo(self.scheduler.cpuSyncTimeline, vk.VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT, self.scheduler.totalFrames + 1);

        const cmdSubmitInf = cmd.createSubmitInfo();
        const submitInf = vk.VkSubmitInfo2{
            .sType = vk.VK_STRUCTURE_TYPE_SUBMIT_INFO_2,
            .waitSemaphoreInfoCount = @intCast(targets.len),
            .pWaitSemaphoreInfos = &waitInfos,
            .commandBufferInfoCount = 1,
            .pCommandBufferInfos = &cmdSubmitInf,
            .signalSemaphoreInfoCount = @intCast(targets.len + 1), // Swapchains + 1 Timeline
            .pSignalSemaphoreInfos = &signalInfos,
        };
        try vh.check(vk.vkQueueSubmit2(self.context.graphicsQ, 1, &submitInf, null), "Failed main submission");
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id.val) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders);
    }

    pub fn createBuffer(self: *Renderer, bufInf: Buffer.BufInf) !void {
        try self.resMan.createBuffer(bufInf);
    }

    pub fn updateBuffer(self: *Renderer, bufInf: Buffer.BufInf, data: anytype) !void {
        try self.resMan.updateBuffer(bufInf, data);
    }

    pub fn createTexture(self: *Renderer, texInf: Texture.TexInf) !void {
        try self.resMan.createTexture(texInf);
    }
};

fn createSemaphoreSubmitInfo(semaphore: vk.VkSemaphore, stageMask: u64, value: u64) vk.VkSemaphoreSubmitInfo {
    return .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = stageMask, .value = value };
}
