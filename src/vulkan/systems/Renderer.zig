const MemoryManager = @import("../../core/MemoryManager.zig").MemoryManager;
const LoadedShader = @import("../../core/ShaderCompiler.zig").LoadedShader;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const Swapchain = @import("../components/Swapchain.zig").Swapchain;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const Texture = @import("../components//Texture.zig").Texture;
const Command = @import("../components/Command.zig").Command;
const Window = @import("../../platform/Window.zig").Window;
const RenderGraph = @import("RenderGraph.zig").RenderGraph;
const Buffer = @import("../components//Buffer.zig").Buffer;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Pass = @import("../components/Pass.zig").Pass;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const Allocator = std.mem.Allocator;
const vh = @import("Helpers.zig");
const std = @import("std");

pub const Renderer = struct {
    alloc: Allocator,
    arenaAlloc: Allocator,
    context: Context,
    resMan: ResourceManager,
    renderGraph: RenderGraph,
    shaderMan: ShaderManager,
    swapMan: SwapchainManager,
    scheduler: Scheduler,
    passes: std.array_list.Managed(Pass),

    pub fn init(memoryMan: *MemoryManager) !Renderer {
        const alloc = memoryMan.getAllocator();
        const context = try Context.init(alloc);
        const resMan = try ResourceManager.init(alloc, &context);

        return .{
            .alloc = alloc,
            .arenaAlloc = memoryMan.getGlobalArena(),
            .context = context,
            .resMan = resMan,
            .renderGraph = try RenderGraph.init(alloc, &context, &resMan),
            .shaderMan = try ShaderManager.init(alloc, &context, &resMan),
            .scheduler = try Scheduler.init(&context, rc.MAX_IN_FLIGHT),
            .swapMan = try SwapchainManager.init(alloc, &context),
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
        self.passes.deinit();
    }

    pub fn updateWindowStates(self: *Renderer, tempWindows: []const Window) !void {
        for (tempWindows) |tempWindow| {
            if (tempWindow.state == .needDelete or tempWindow.state == .needUpdate) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        var texIds: [rc.MAX_WINDOWS]?Texture.TexId = .{null} ** rc.MAX_WINDOWS;

        for (tempWindows, 0..) |tempWindow, i| {
            switch (tempWindow.state) {
                .needUpdate, .needCreation => try self.swapMan.createSwapchain(&self.context, .{ .window = tempWindow }),
                .needActive, .needInactive => self.swapMan.changeState(tempWindow.id, if (tempWindow.state == .needActive) true else false),
                .needDelete => self.swapMan.removeSwapchain(&.{tempWindow}),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(tempWindow.state)}),
            }
            if (tempWindow.resizeTex == true) texIds[i] = tempWindow.renderTexId;
        }

        if (rc.RENDER_TEX_AUTO_RESIZE == true) {
            for (0..texIds.len) |i| {
                if (texIds[i] == null) break;

                const texId = texIds[i].?;
                const passImg = try self.resMan.getTexturePtr(texId);
                try self.updateRenderTexture(texId, passImg);
            }
        }
    }

    pub fn updateRenderTexture(self: *Renderer, texId: Texture.TexId, tex: *Texture) !void {
        const old = tex.base.extent;
        const new = self.swapMan.getMaxRenderExtent(texId);

        if (new.width != old.width or new.height != old.height) {
            const imgInf = Texture.TexInf{ .id = texId, .width = new.width, .height = new.height, .depth = 1, .typ = tex.base.texType, .mem = .Gpu };
            try self.resMan.replaceTexture(texId, imgInf);
            std.debug.print("Render Texture ID {} recreated {}x{} to {}x{}\n", .{ texId.val, old.width, old.height, new.width, new.height });
        }
    }

    pub fn createPasses(self: *Renderer, passes: []const Pass) !void {
        for (passes) |pass| {
            if (true == true) { //self.shaderMan.isPassValid(pass)
                try self.passes.append(pass);
            } else std.debug.print("Error: Pass ShaderLayout does not match Pass Type -> not appended\n", .{});
        }
    }

    pub fn draw(self: *Renderer, frameData: FrameData) !void {
        try self.scheduler.waitForGPU();
        const flightId = self.scheduler.flightId;

        if (try self.swapMan.updateTargets(flightId, &self.context) == false) return;
        const targets = self.swapMan.getTargets();

        const cmd = try self.renderGraph.recordFrame(flightId, &self.resMan, frameData, targets, self.passes.items, &self.shaderMan);

        try self.queueSubmit(&cmd, targets, flightId);
        try self.swapMan.present(targets, self.context.presentQ.handle);

        self.scheduler.nextFrame();
    }

    fn queueSubmit(self: *Renderer, cmd: *const Command, targets: []const *Swapchain, flightId: u8) !void {
        var waitInfos: [rc.MAX_WINDOWS]vk.VkSemaphoreSubmitInfo = undefined;
        var signalInfos: [rc.MAX_WINDOWS + 1]vk.VkSemaphoreSubmitInfo = undefined;
        signalInfos[targets.len] = createSemaphoreSubmitInfo(self.scheduler.cpuSyncTimeline, .AllCmds, self.scheduler.totalFrames + 1);

        for (targets, 0..) |swapchain, i| {
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[flightId], .Transfer, 0);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderDoneSems[swapchain.curIndex], .AllCmds, 0);
        }
        try self.context.graphicsQ.submit(waitInfos[0..targets.len], cmd.createSubmitInfo(), signalInfos[0 .. targets.len + 1]);
    }

    pub fn addShaders(self: *Renderer, loadedShaders: []const LoadedShader) !void {
        for (loadedShaders) |loadedShader| {
            if (self.shaderMan.isShaderIdUsed(loadedShader.shaderInf.id.val) == true) {
                _ = vk.vkDeviceWaitIdle(self.context.gpi);
                break;
            }
        }
        try self.shaderMan.createShaders(loadedShaders);
    }

    pub fn createBuffers(self: *Renderer, bufInfos: []const Buffer.BufInf) !void {
        for (bufInfos) |bufInf| try self.resMan.createBuffer(bufInf);
    }

    pub fn updateBuffer(self: *Renderer, bufInf: Buffer.BufInf, data: anytype) !void {
        try self.resMan.updateBuffer(bufInf, data);
    }

    pub fn createTexture(self: *Renderer, texInfos: []const Texture.TexInf) !void {
        for (texInfos) |texInf| try self.resMan.createTexture(texInf);
    }
};

fn createSemaphoreSubmitInfo(semaphore: vk.VkSemaphore, pipeStage: vh.PipeStage, value: u64) vk.VkSemaphoreSubmitInfo {
    return .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = @intFromEnum(pipeStage), .value = value };
}
