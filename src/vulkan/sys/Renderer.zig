const Swapchain = @import("../types/base/Swapchain.zig").Swapchain;
const MemoryManager = @import("../../core/MemoryManager.zig").MemoryManager;
const LoadedShader = @import("../../core/ShaderCompiler.zig").LoadedShader;
const SwapchainManager = @import("SwapchainManager.zig").SwapchainManager;
const ResourceManager = @import("ResourceManager.zig").ResourceManager;
const ShaderManager = @import("ShaderManager.zig").ShaderManager;
const Command = @import("../types/base/Command.zig").Command;
const Texture = @import("../types/res/Texture.zig").Texture;
const Window = @import("../../platform/Window.zig").Window;
const RenderGraph = @import("RenderGraph.zig").RenderGraph;
const Buffer = @import("../types/res/Buffer.zig").Buffer;
const Queue = @import("../types/base/Queue.zig").Queue;
const Pass = @import("../types/base/Pass.zig").Pass;
const rc = @import("../../configs/renderConfig.zig");
const FrameData = @import("../../App.zig").FrameData;
const Scheduler = @import("Scheduler.zig").Scheduler;
const Context = @import("Context.zig").Context;
const vk = @import("../../modules/vk.zig").c;
const vkE = @import("../help/Enums.zig");
const Allocator = std.mem.Allocator;
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

        for (tempWindows, 0..) |window, i| {
            switch (window.state) {
                .needCreation => try self.swapMan.createSwapchain(window),
                .needUpdate => try self.swapMan.recreateSwapchain(window.id, window.extent),
                .needDelete => self.swapMan.removeSwapchains(window.id),
                .needActive, .needInactive => self.swapMan.changeState(window.id, if (window.state == .needActive) true else false),
                else => std.debug.print("Warning: Window State {s} cant be handled in Renderer\n", .{@tagName(window.state)}),
            }
            if (window.resizeTex == true) texIds[i] = window.renderTexId;
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

    pub fn draw(self: *Renderer, frameData: FrameData) !void {
        try self.scheduler.waitForGPU();
        const flightId = self.scheduler.flightId;

        try self.renderGraph.cmdMan.printQueryResults(flightId);

        if (try self.swapMan.updateTargets(flightId) == false) return;
        const targets = self.swapMan.getTargets();

        const cmd = try self.renderGraph.recordFrame(self.passes.items, flightId, frameData, targets, &self.resMan, &self.shaderMan);

        try self.queueSubmit(&cmd, targets, flightId, self.context.graphicsQ);
        try self.present(targets, self.context.presentQ);

        self.scheduler.nextFrame();
    }

    fn queueSubmit(self: *Renderer, cmd: *const Command, targets: []const *Swapchain, flightId: u8, queue: Queue) !void {
        var waitInfos: [rc.MAX_WINDOWS]vk.VkSemaphoreSubmitInfo = undefined;
        var signalInfos: [rc.MAX_WINDOWS + 1]vk.VkSemaphoreSubmitInfo = undefined;
        signalInfos[targets.len] = createSemaphoreSubmitInfo(self.scheduler.cpuSyncTimeline, .AllCmds, self.scheduler.totalFrames + 1);

        for (targets, 0..) |swapchain, i| {
            waitInfos[i] = createSemaphoreSubmitInfo(swapchain.imgRdySems[flightId], .Transfer, 0);
            signalInfos[i] = createSemaphoreSubmitInfo(swapchain.renderDoneSems[swapchain.curIndex], .AllCmds, 0);
        }
        const cmdSlice = &[_]vk.VkCommandBufferSubmitInfo{cmd.createSubmitInfo()};
        try queue.submit(waitInfos[0..targets.len], cmdSlice, signalInfos[0 .. targets.len + 1]);
    }

    fn present(_: *Renderer, targets: []const *const Swapchain, queue: Queue) !void {
        var handles: [rc.MAX_WINDOWS]vk.VkSwapchainKHR = undefined;
        var imgIndices: [rc.MAX_WINDOWS]u32 = undefined;
        var waitSems: [rc.MAX_WINDOWS]vk.VkSemaphore = undefined;

        for (targets, 0..) |swapchain, i| {
            handles[i] = swapchain.handle;
            imgIndices[i] = swapchain.curIndex;
            waitSems[i] = swapchain.renderDoneSems[swapchain.curIndex];
        }
        try queue.present(handles[0..targets.len], imgIndices[0..targets.len], waitSems[0..targets.len]);
    }

    pub fn createPasses(self: *Renderer, passes: []const Pass) !void {
        for (passes) |pass| {
            if (self.shaderMan.isPassValid(pass) == true) {
                try self.passes.append(pass);
            } else {
                std.debug.print("Error: Pass ShaderLayout does not match Pass Type -> not appended\n", .{});
                return error.PassNotValid;
            }
        }
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

fn createSemaphoreSubmitInfo(semaphore: vk.VkSemaphore, pipeStage: vkE.PipeStage, value: u64) vk.VkSemaphoreSubmitInfo {
    return .{ .sType = vk.VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO, .semaphore = semaphore, .stageMask = @intFromEnum(pipeStage), .value = value };
}
